local project = require('user.project')

local M = {}

local CONFIG_FILENAME = '.nvim-dap.json'
local CPP_EXTENSIONS = {
  c = true,
  cc = true,
  cpp = true,
  cxx = true,
  h = true,
  hh = true,
  hpp = true,
  hxx = true,
}
local lldb_dap_path

local function is_config_file(path)
  return path and path ~= '' and vim.fs.basename(path) == CONFIG_FILENAME
end

local function pretty_json(value, indent)
  indent = indent or 0
  local prefix = string.rep('  ', indent)
  local child_prefix = string.rep('  ', indent + 1)

  if value == nil then
    return 'null'
  end

  if type(value) == 'string' then
    return vim.json.encode(value)
  end

  if type(value) == 'number' or type(value) == 'boolean' then
    return tostring(value)
  end

  if vim.islist(value) then
    if #value == 0 then
      return '[]'
    end

    local parts = { '[' }
    for index, item in ipairs(value) do
      local suffix = index < #value and ',' or ''
      table.insert(parts, child_prefix .. pretty_json(item, indent + 1) .. suffix)
    end
    table.insert(parts, prefix .. ']')
    return table.concat(parts, '\n')
  end

  local keys = vim.tbl_keys(value)
  table.sort(keys)
  if #keys == 0 then
    return '{}'
  end

  local parts = { '{' }
  for index, key in ipairs(keys) do
    local suffix = index < #keys and ',' or ''
    table.insert(parts, child_prefix .. vim.json.encode(key) .. ': ' .. pretty_json(value[key], indent + 1) .. suffix)
  end
  table.insert(parts, prefix .. '}')
  return table.concat(parts, '\n')
end

local function config_path(path_or_bufnr)
  return project.config_path(CONFIG_FILENAME, path_or_bufnr)
end

local function read_text(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end

  return table.concat(vim.fn.readfile(path), '\n')
end

local function xml_tag(text, tag)
  if not text then
    return nil
  end

  return text:match('<' .. tag .. '>(.-)</' .. tag .. '>')
end

local function package_name_for_file(path)
  local lines = vim.fn.readfile(path, '', 120)
  for _, line in ipairs(lines) do
    local package_name = line:match('^%s*package%s+([%w_%.]+)%s*;')
    if package_name then
      return package_name
    end
  end
end

local function detect_java_candidates(root, relative_root)
  local candidates = {}
  local java_root = vim.fs.joinpath(root, relative_root)
  local stat = vim.uv.fs_stat(java_root)
  if not stat or stat.type ~= 'directory' then
    return candidates
  end

  local paths = vim.fs.find(function(name)
    return name:sub(-5) == '.java'
  end, {
    path = java_root,
    type = 'file',
    limit = 50,
  })

  for _, path in ipairs(paths) do
    local text = read_text(path) or ''
    if text:find('public static void main', 1, true) or text:find('@SpringBootApplication', 1, true) then
      local package_name = package_name_for_file(path)
      local class_name = vim.fn.fnamemodify(path, ':t:r')
      local fqn = package_name and (package_name .. '.' .. class_name) or class_name
      table.insert(candidates, fqn)
    end
  end

  table.sort(candidates)
  return candidates
end

local function detect_test_candidates(root)
  local candidates = {}
  local test_root = vim.fs.joinpath(root, 'src/test/java')
  local stat = vim.uv.fs_stat(test_root)
  if not stat or stat.type ~= 'directory' then
    return candidates
  end

  local paths = vim.fs.find(function(name)
    return name:sub(-9) == 'Test.java'
  end, {
    path = test_root,
    type = 'file',
    limit = 50,
  })

  for _, path in ipairs(paths) do
    local package_name = package_name_for_file(path)
    local class_name = vim.fn.fnamemodify(path, ':t:r')
    local fqn = package_name and (package_name .. '.' .. class_name) or class_name
    table.insert(candidates, fqn)
  end

  table.sort(candidates)
  return candidates
end

local function detect_cmake_info(root)
  local info = {
    projectName = nil,
    executableTargets = {},
  }

  local cmake_text = read_text(vim.fs.joinpath(root, 'CMakeLists.txt'))
  if not cmake_text then
    return info
  end

  info.projectName = cmake_text:match('project%s*%(%s*([%w_%-%.]+)')
  for target in cmake_text:gmatch('add_executable%s*%(%s*([%w_%-%.]+)') do
    table.insert(info.executableTargets, target)
  end

  table.sort(info.executableTargets)
  return info
end

local function detect_project_info(path_or_bufnr)
  local root = project.root(path_or_bufnr)
  local info = {
    root = root,
    rootMarker = vim.fs.basename(root),
    buildTool = nil,
    maven = {},
    gradle = {},
    cmake = {},
    eclipse = {},
    java = {},
  }

  local pom_text = read_text(vim.fs.joinpath(root, 'pom.xml'))
  if pom_text then
    info.buildTool = 'maven'
    local direct_pom = pom_text:gsub('<parent>[%s%S]-</parent>', '')
    info.maven.groupId = xml_tag(direct_pom, 'groupId') or xml_tag(pom_text, 'groupId')
    info.maven.artifactId = xml_tag(direct_pom, 'artifactId') or xml_tag(pom_text, 'artifactId')
    info.maven.name = xml_tag(direct_pom, 'name') or xml_tag(pom_text, 'name')
  end

  local gradle_settings = read_text(vim.fs.joinpath(root, 'settings.gradle'))
    or read_text(vim.fs.joinpath(root, 'settings.gradle.kts'))
    or read_text(vim.fs.joinpath(root, 'build.gradle'))
    or read_text(vim.fs.joinpath(root, 'build.gradle.kts'))
  if gradle_settings then
    info.buildTool = info.buildTool or 'gradle'
    info.gradle.projectName = gradle_settings:match("rootProject%%.name%s*=%s*['\"]([^'\"]+)['\"]")
  end

  info.cmake = detect_cmake_info(root)
  if #info.cmake.executableTargets > 0 then
    info.buildTool = info.buildTool or 'cmake'
  end

  local eclipse_text = read_text(vim.fs.joinpath(root, '.project'))
  if eclipse_text then
    info.eclipse.projectName = xml_tag(eclipse_text, 'name')
  end

  info.java.mainClasses = detect_java_candidates(root, 'src/main/java')
  info.java.testClasses = detect_test_candidates(root)

  return info
end

local function default_project_name(info)
  return info.eclipse.projectName
    or info.gradle.projectName
    or info.cmake.projectName
    or vim.fs.basename(info.root)
    or info.maven.artifactId
    or info.maven.name
end

local function detect_debug_kind(path_or_bufnr, info)
  local path
  if type(path_or_bufnr) == 'number' then
    path = project.path_from_buf(path_or_bufnr)
  elseif type(path_or_bufnr) == 'string' then
    path = path_or_bufnr
  else
    path = project.path_from_buf(0)
  end

  local ext = (path and vim.fn.fnamemodify(path, ':e') or ''):lower()
  if CPP_EXTENSIONS[ext] then
    return 'cpp'
  end
  if ext == 'java' then
    return 'java'
  end
  if #info.java.mainClasses > 0 and #info.cmake.executableTargets == 0 then
    return 'java'
  end
  if #info.cmake.executableTargets > 0 then
    return 'cpp'
  end
  return 'java'
end

local function java_config_template(info)
  local main_class = info.java.mainClasses[1] or 'com.example.Main'
  local build_tool = info.buildTool or 'unknown'

  return {
    _desc = 'Default launch + port configs generated from the current build files.',
    _detected = {
      root = '.',
      rootName = vim.fs.basename(info.root),
      buildTool = build_tool,
      maven = info.maven,
      gradle = info.gradle,
      cmake = info.cmake,
      eclipse = info.eclipse,
      java = info.java,
    },
    configurations = {
      {
        name = 'port',
        type = 'java',
        request = 'attach',
        hostName = '127.0.0.1',
        port = 5005,
        mainClass = main_class,
      },
      {
        name = 'launch',
        type = 'java',
        request = 'launch',
        cwd = '${projectRoot}',
        mainClass = main_class,
      },
    },
  }
end

local function cpp_config_template(info)
  local target = info.cmake.executableTargets[1] or default_project_name(info) or 'app'
  local build_tool = info.buildTool or 'cmake'

  return {
    _desc = 'Default launch + process-pick configs generated from the current build files.',
    _detected = {
      root = '.',
      rootName = vim.fs.basename(info.root),
      buildTool = build_tool,
      cmake = info.cmake,
    },
    configurations = {
      {
        name = 'launch',
        type = 'lldb',
        request = 'launch',
        cwd = '${projectRoot}',
        program = '${projectRoot}/build/' .. target,
        args = {},
      },
      {
        name = 'attach-process',
        type = 'lldb',
        request = 'attach',
        cwd = '${projectRoot}',
        program = '${projectRoot}/build/' .. target,
        processQuery = target,
      },
    },
  }
end

local function config_template(info, path_or_bufnr)
  if detect_debug_kind(path_or_bufnr, info) == 'cpp' then
    return cpp_config_template(info)
  end
  return java_config_template(info)
end

local function ensure_config_file(path_or_bufnr)
  local path = config_path(path_or_bufnr)
  local stat = vim.uv.fs_stat(path)
  if stat and stat.size > 0 then
    return path
  end

  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  local template = config_template(detect_project_info(path_or_bufnr), path_or_bufnr)
  vim.fn.writefile(vim.split(pretty_json(template), '\n', { plain = true }), path)
  return path
end

local function decode_config(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return { configurations = {} }
  end

  local lines = vim.fn.readfile(path)
  if #lines == 0 then
    return { configurations = {} }
  end

  local ok, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not ok or type(decoded) ~= 'table' then
    error('Invalid DAP config JSON: ' .. path)
  end

  decoded.configurations = vim.islist(decoded.configurations) and decoded.configurations or {}
  return decoded
end

local function source_context_buf(path_or_bufnr)
  if type(path_or_bufnr) == 'number' then
    local current_path = project.path_from_buf(path_or_bufnr) or ''
    if current_path ~= '' and not is_config_file(current_path) then
      return path_or_bufnr
    end
  end

  local alternate = vim.fn.bufnr('#')
  if alternate > 0 then
    local alternate_path = project.path_from_buf(alternate) or ''
    if alternate_path ~= '' and not is_config_file(alternate_path) then
      return alternate
    end
  end

  local root = project.root(path_or_bufnr)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == '' then
      local path = project.path_from_buf(bufnr) or ''
      if path ~= '' and not is_config_file(path) and project.root(path) == root then
        return bufnr
      end
    end
  end

  return type(path_or_bufnr) == 'number' and path_or_bufnr or 0
end

local function placeholder_vars(path_or_bufnr)
  local source_bufnr = source_context_buf(path_or_bufnr)
  local path = project.path_from_buf(source_bufnr) or ''
  local root = project.root(path)
  return {
    projectRoot = root,
    file = path,
    fileDirname = path ~= '' and vim.fn.fnamemodify(path, ':h') or root,
    fileBasename = path ~= '' and vim.fn.fnamemodify(path, ':t') or '',
    relativeFile = path ~= '' and project.relative(path, root) or '',
  }
end

local function expand_placeholders(value, vars)
  if type(value) == 'string' then
    return (value:gsub('%${([%w_]+)}', function(name)
      return vars[name] or '${' .. name .. '}'
    end))
  end

  if type(value) ~= 'table' then
    return value
  end

  local result = vim.islist(value) and {} or {}
  if vim.islist(value) then
    for index, item in ipairs(value) do
      result[index] = expand_placeholders(item, vars)
    end
    return result
  end

  for key, item in pairs(value) do
    result[key] = expand_placeholders(item, vars)
  end
  return result
end

local function normalize_config(config)
  local normalized = {}
  for key, value in pairs(config) do
    if not tostring(key):match('^_')
      and value ~= nil
      and not (type(value) == 'string' and value == '')
    then
      normalized[key] = value
    end
  end

  if type(normalized.port) == 'string' then
    normalized.port = tonumber(normalized.port) or normalized.port
  end

  if normalized.type == 'java' and vim.islist(normalized.args) then
    if #normalized.args == 0 then
      normalized.args = nil
    else
      local parts = {}
      for _, item in ipairs(normalized.args) do
        table.insert(parts, tostring(item))
      end
      normalized.args = table.concat(parts, ' ')
    end
  end

  if type(normalized.pid) == 'string' then
    normalized.pid = tonumber(normalized.pid) or normalized.pid
  end

  return normalized
end

local function shell_command_output(cmd)
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil, result.stderr or ('Command failed: ' .. table.concat(cmd, ' '))
  end
  return vim.trim(result.stdout or '')
end

local function find_lldb_dap()
  if lldb_dap_path then
    return lldb_dap_path
  end

  local exepath = vim.fn.exepath('lldb-dap')
  if exepath ~= '' then
    lldb_dap_path = exepath
    return lldb_dap_path
  end

  if vim.fn.executable('xcrun') == 1 then
    local resolved = shell_command_output({ 'xcrun', '--find', 'lldb-dap' })
    if resolved and resolved ~= '' then
      lldb_dap_path = resolved
      return lldb_dap_path
    end
  end

  return nil
end

local function ensure_native_dap()
  local dap = require('dap')
  if dap.adapters.lldb ~= nil then
    return true
  end

  local command = find_lldb_dap()
  if not command then
    vim.notify('Could not find lldb-dap. Install Xcode Command Line Tools or make lldb-dap available in PATH.', vim.log.levels.ERROR)
    return false
  end

  dap.adapters.lldb = {
    type = 'executable',
    command = command,
    name = 'lldb',
  }
  return true
end

local function process_thread_count(pid)
  local result = vim.system({ 'ps', '-M', '-p', tostring(pid) }, { text = true }):wait()
  if result.code ~= 0 or not result.stdout or result.stdout == '' then
    return nil
  end

  local lines = 0
  for _ in result.stdout:gmatch('[^\n]+') do
    lines = lines + 1
  end

  if lines > 1 then
    return lines - 1
  end
end

local function matching_processes(query)
  local stdout, err = shell_command_output({ 'ps', '-axo', 'pid=,command=' })
  if not stdout then
    return nil, err
  end

  local matches = {}
  local needle = query:lower()
  for line in stdout:gmatch('[^\n]+') do
    local pid, command = line:match('^%s*(%d+)%s+(.*)$')
    if pid and command and command ~= '' and command:lower():find(needle, 1, true) then
      table.insert(matches, {
        pid = tonumber(pid),
        command = command,
        threads = process_thread_count(pid),
      })
    end
  end

  table.sort(matches, function(left, right)
    return left.pid < right.pid
  end)

  return matches
end

local function pick_process(config, callback)
  local default_query = config.processQuery or config.name or vim.fs.basename(config.program or project.root(0))
  vim.ui.input({
    prompt = 'Search process: ',
    default = default_query,
  }, function(query)
    query = vim.trim(query or '')
    if query == '' then
      callback(nil)
      return
    end

    local matches, err = matching_processes(query)
    if not matches then
      vim.notify(err, vim.log.levels.ERROR)
      callback(nil)
      return
    end

    if #matches == 0 then
      vim.notify('No process matched: ' .. query, vim.log.levels.WARN)
      callback(nil)
      return
    end

    if #matches == 1 then
      callback(matches[1].pid)
      return
    end

    vim.ui.select(matches, {
      prompt = 'Select process',
      format_item = function(item)
        local thread_text = item.threads and (' threads=' .. item.threads) or ''
        return string.format('pid=%d%s %s', item.pid, thread_text, item.command)
      end,
    }, function(choice)
      callback(choice and choice.pid or nil)
    end)
  end)
end

local function starts_with_path(path, root)
  return path == root or path:sub(1, #root + 1) == root .. '/'
end

local function find_jdtls_client(path)
  local best_client
  local best_root_len = -1

  for _, client in ipairs(vim.lsp.get_clients({ name = 'jdtls' })) do
    local roots = {}

    if client.config and client.config.root_dir then
      table.insert(roots, client.config.root_dir)
    end

    for _, folder in ipairs(client.workspace_folders or {}) do
      table.insert(roots, vim.uri_to_fname(folder.uri))
    end

    for _, root in ipairs(roots) do
      local normalized_root = vim.fs.normalize(root)
      if normalized_root and starts_with_path(path, normalized_root) and #normalized_root > best_root_len then
        best_client = client
        best_root_len = #normalized_root
      end
    end
  end

  return best_client
end

local function find_java_buffer(root)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == '' then
      local path = project.path_from_buf(bufnr) or ''
      if path:sub(-5) == '.java' and project.root(path) == root then
        return bufnr
      end
    end
  end
end

local function prepare_java_dap(path_or_bufnr)
  local ok, java = pcall(require, 'java')
  if not (ok and java.dap and java.dap.config_dap) then
    return true
  end

  local source_bufnr = source_context_buf(path_or_bufnr)
  local source_path = project.path_from_buf(source_bufnr) or ''
  local client = source_path ~= '' and find_jdtls_client(source_path) or nil
  if not client then
    vim.notify('Java debug requires an active jdtls client. Open a Java file in this project first, wait for jdtls to attach, then retry.', vim.log.levels.WARN)
    return false
  end

  local java_bufnr = source_bufnr
  if source_path:sub(-5) ~= '.java' then
    java_bufnr = find_java_buffer(project.root(source_path))
  end

  local ok_config, err = pcall(function()
    if java_bufnr and java_bufnr > 0 then
      vim.api.nvim_buf_call(java_bufnr, function()
        java.dap.config_dap()
      end)
      return
    end

    java.dap.config_dap()
  end)

  if not ok_config then
    vim.notify('Java DAP setup failed: ' .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  return true
end

local function start_config(config, path_or_bufnr)
  local dap = require('dap')
  local vars = placeholder_vars(path_or_bufnr)
  local expanded = expand_placeholders(normalize_config(config), vars)
  local ok_ui, dap_ui = pcall(require, 'user.dap_ui')
  if ok_ui and dap_ui.set_project_root then
    dap_ui.set_project_root(vars.projectRoot)
    dap_ui.ensure_listeners()
  end

  if expanded.type == 'java' and not prepare_java_dap(path_or_bufnr) then
    return
  end

  if expanded.type == 'lldb' then
    if not ensure_native_dap() then
      return
    end

    if expanded.request == 'attach' and not expanded.pid then
      pick_process(expanded, function(pid)
        if not pid then
          return
        end

        local attach_config = vim.deepcopy(expanded)
        attach_config.pid = pid
        attach_config.processQuery = nil
        dap.run(attach_config)
      end)
      return
    end
  end

  dap.run(expanded)
end

function M.edit_config(path_or_bufnr)
  local path = ensure_config_file(path_or_bufnr)
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
end

function M.start(path_or_bufnr)
  local path = ensure_config_file(path_or_bufnr)
  local config = decode_config(path)
  local configurations = config.configurations or {}

  if #configurations == 0 then
    vim.notify('No debug configurations found in ' .. path, vim.log.levels.WARN)
    return
  end

  if #configurations == 1 then
    start_config(configurations[1], path_or_bufnr)
    return
  end

  vim.ui.select(configurations, {
    prompt = 'Select debug configuration',
    format_item = function(item)
      return string.format('%s (%s/%s)', item.name or '<unnamed>', item.type or '?', item.request or '?')
    end,
  }, function(choice)
    if not choice then
      return
    end
    start_config(choice, path_or_bufnr)
  end)
end

function M.toggle_breakpoint()
  require('dap').toggle_breakpoint()
end

function M.setup()
  vim.api.nvim_create_user_command('DebugConfigEdit', function()
    M.edit_config(0)
  end, {
    desc = 'Create or edit the project-local DAP config list',
  })

  vim.api.nvim_create_user_command('DebugStart', function()
    M.start(0)
  end, {
    desc = 'Start a debug session from the project-local config list',
  })

  vim.api.nvim_create_user_command('DebugToggleBreakpoint', function()
    M.toggle_breakpoint()
  end, {
    desc = 'Toggle a DAP breakpoint on the current line',
  })
end

return M
