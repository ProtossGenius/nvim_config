local project = require('user.project')

local M = {}

local CONFIG_FILENAME = '.nvim-dap.json'

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

local function detect_project_info(path_or_bufnr)
  local root = project.root(path_or_bufnr)
  local info = {
    root = root,
    rootMarker = vim.fs.basename(root),
    maven = {},
    eclipse = {},
    java = {},
  }

  local pom_text = read_text(vim.fs.joinpath(root, 'pom.xml'))
  if pom_text then
    local direct_pom = pom_text:gsub('<parent>[%s%S]-</parent>', '')
    info.maven.groupId = xml_tag(direct_pom, 'groupId') or xml_tag(pom_text, 'groupId')
    info.maven.artifactId = xml_tag(direct_pom, 'artifactId') or xml_tag(pom_text, 'artifactId')
    info.maven.name = xml_tag(direct_pom, 'name') or xml_tag(pom_text, 'name')
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
  return info.eclipse.projectName or info.maven.artifactId or info.maven.name or vim.fs.basename(info.root)
end

local function config_template(info)
  local project_name = default_project_name(info)
  local main_class = info.java.mainClasses[1] or 'com.example.demo.DemoApplication'
  local test_class = info.java.testClasses[1] or 'com.example.demo.service.UserServiceSmokeTest'

  return {
    _desc = {
      'Snaps: launch, attach-port, test-class.',
      'Copy one snap into configurations, then replace the placeholder text values.',
      'Default configuration below attaches to a running JVM debug port.',
    },
    _detected = {
      root = info.root,
      maven = info.maven,
      eclipse = info.eclipse,
      java = info.java,
    },
    snaps = {
      launch = {
        name = 'Launch name, e.g. demo-app',
        type = 'java',
        request = 'launch',
        cwd = '${projectRoot}',
        projectName = 'Project name, e.g. ' .. project_name,
        mainClass = 'Main class, e.g. ' .. main_class,
        args = {
          'Args array, e.g. --spring.profiles.active=dev',
        },
      },
      ['attach-port'] = {
        name = 'Attach name, e.g. local-5005',
        type = 'java',
        request = 'attach',
        hostName = 'Debug host, e.g. 127.0.0.1',
        port = 'Debug port, e.g. 5005',
        projectName = 'Project name, e.g. ' .. project_name,
      },
      ['test-class'] = {
        name = 'Test name, e.g. smoke-test',
        type = 'java',
        request = 'launch',
        cwd = '${projectRoot}',
        projectName = 'Project name, e.g. ' .. project_name,
        mainClass = 'Test class, e.g. ' .. test_class,
      },
    },
    configurations = {
      {
        name = 'attach-port',
        type = 'java',
        request = 'attach',
        hostName = '127.0.0.1',
        port = 5005,
        projectName = project_name,
      },
    },
  }
end

local function ensure_config_file(path_or_bufnr)
  local path = config_path(path_or_bufnr)
  local stat = vim.uv.fs_stat(path)
  if stat and stat.size > 0 then
    return path
  end

  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  local template = config_template(detect_project_info(path_or_bufnr))
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

local function placeholder_vars()
  local path = project.path_from_buf(0) or ''
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
    if key ~= 'name'
      and not tostring(key):match('^_')
      and value ~= nil
      and not (type(value) == 'string' and value == '')
    then
      normalized[key] = value
    end
  end

  if type(normalized.port) == 'string' then
    normalized.port = tonumber(normalized.port) or normalized.port
  end
  return normalized
end

local function prepare_java_dap()
  local ok, java = pcall(require, 'java')
  if ok and java.dap and java.dap.config_dap then
    java.dap.config_dap()
  end
end

local function start_config(config)
  local dap = require('dap')
  local vars = placeholder_vars()
  local expanded = expand_placeholders(normalize_config(config), vars)

  if expanded.type == 'java' then
    prepare_java_dap()
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
    start_config(configurations[1])
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
    start_config(choice)
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
