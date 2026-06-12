local uv = vim.uv or vim.loop
local project = require('user.project')

local M = {}

local runtime_scan_patterns = {
  '/Library/Java/JavaVirtualMachines/*/Contents/Home',
  '/usr/lib/jvm/*',
  vim.fn.expand('~/.sdkman/candidates/java/*'),
  vim.fn.expand('~/.jdks/*/Contents/Home'),
  vim.fn.expand('~/.jdks/*'),
}

local managed_runtime_scan_patterns = {
  vim.fs.joinpath(vim.fn.stdpath('data'), 'nvim-java', 'packages', 'openjdk', '*', 'jdk-*', 'Contents', 'Home'),
  vim.fs.joinpath(vim.fn.stdpath('data'), 'nvim-java', 'packages', 'openjdk', '*', 'jdk-*'),
}

local java_lsp_repo_dir = vim.fs.normalize(vim.env.JAVA_LSP_REPO_DIR or vim.fn.expand('~/workspace/java-lsp'))
local java_lsp_bin_dir = vim.fs.joinpath(vim.fn.stdpath('data'), 'java-lsp', 'bin')
local java_lsp_bin_path = vim.fs.joinpath(java_lsp_bin_dir, 'java-lsp')
local java_lsp_module = 'github.com/ProtossGenius/java-lsp/cmd/java-lsp@latest'

local state

local function fs_stat(path)
  return path ~= '' and uv.fs_stat(path) or nil
end

local function is_dir(path)
  local stat = fs_stat(path)
  return stat and stat.type == 'directory' or false
end

local function is_file(path)
  local stat = fs_stat(path)
  return stat and stat.type == 'file' or false
end

local function read_file_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return {}
  end

  return lines
end

local function go_environment()
  local env = vim.fn.environ()
  env.GOBIN = java_lsp_bin_dir
  return env
end

local function progress_echo(message, hl)
  vim.schedule(function()
    vim.api.nvim_echo({ { message, hl or 'ModeMsg' } }, false, {})
  end)
end

local function project_label(root)
  return vim.fn.fnamemodify(root, ':t')
end

local function install_java_lsp(opts)
  opts = opts or {}
  if vim.fn.executable('go') ~= 1 then
    vim.notify('Go executable not found; cannot install java-lsp.', vim.log.levels.ERROR)
    return nil
  end

  vim.fn.mkdir(java_lsp_bin_dir, 'p')

  local cmd
  local cwd
  if is_dir(java_lsp_repo_dir) and is_file(vim.fs.joinpath(java_lsp_repo_dir, 'go.mod')) then
    cmd = { 'go', 'install', './cmd/java-lsp' }
    cwd = java_lsp_repo_dir
  else
    cmd = { 'go', 'install', java_lsp_module }
  end

  if opts.notify ~= false then
    vim.notify('Installing java-lsp with Go...', vim.log.levels.INFO)
  end

  local proc = vim.system(cmd, {
    cwd = cwd,
    env = go_environment(),
    text = true,
  }):wait()

  if proc.code ~= 0 then
    local output = table.concat({
      proc.stdout or '',
      proc.stderr or '',
    }, '\n')
    vim.notify('Failed to install java-lsp:\n' .. output, vim.log.levels.ERROR)
    return nil
  end

  if opts.notify ~= false then
    vim.notify('java-lsp installed at ' .. java_lsp_bin_path, vim.log.levels.INFO)
  end

  return java_lsp_bin_path
end

local function runtime_name(major)
  if major == 8 then
    return 'JavaSE-1.8'
  end

  return 'JavaSE-' .. major
end

local function storage_project_key(root)
  local normalized = vim.fs.normalize(root or vim.fn.getcwd())
  local name = vim.fn.fnamemodify(normalized, ':t')
  local digest = vim.fn.sha256(normalized):sub(1, 12)
  return string.format('%s-%s', name, digest)
end

local function major_from_version(version)
  if not version or version == '' then
    return nil
  end

  local major = version:match('^(%d+)')
  if major == '1' then
    major = version:match('^1%.(%d+)')
  end

  return tonumber(major)
end

local function version_from_release(java_home)
  local release_file = vim.fs.joinpath(java_home, 'release')
  if not is_file(release_file) then
    return nil
  end

  for _, line in ipairs(read_file_lines(release_file)) do
    local version = line:match('^JAVA_VERSION="([^"]+)"')
    if version then
      return version
    end
  end
end

local function add_runtime(runtimes, seen, java_home, opts)
  opts = opts or {}
  if not java_home or java_home == '' then
    return
  end

  java_home = vim.fs.normalize(java_home)
  if not is_dir(java_home) or seen[java_home] then
    return
  end

  local version = opts.version or version_from_release(java_home)
  local major = major_from_version(version)
  if not major then
    return
  end

  seen[java_home] = true
  table.insert(runtimes, {
    name = runtime_name(major),
    path = java_home,
    default = false,
    _major = major,
    _preferred = opts.preferred or false,
    _source = opts.source or 'system',
  })
end

local function detect_java_runtimes()
  local runtimes = {}
  local seen = {}

  if vim.env.JAVA_HOME and vim.env.JAVA_HOME ~= '' then
    add_runtime(runtimes, seen, vim.env.JAVA_HOME, { preferred = true, source = 'system' })
  end

  if vim.fn.has('mac') == 1 and vim.fn.executable('/usr/libexec/java_home') == 1 then
    local proc = vim.system({ '/usr/libexec/java_home', '-V' }, { text = true }):wait()
    local output = table.concat({
      proc.stderr or '',
      proc.stdout or '',
    }, '\n')

    for line in output:gmatch('[^\r\n]+') do
      local version, path = line:match('%s+([%d%.%+_%-]+)[^/]- (/.+)$')
      if path then
        add_runtime(runtimes, seen, path, { version = version, source = 'system' })
      end
    end
  end

  for _, pattern in ipairs(runtime_scan_patterns) do
    for _, path in ipairs(vim.fn.glob(pattern, false, true)) do
      add_runtime(runtimes, seen, path, { source = 'system' })
    end
  end

  for _, pattern in ipairs(managed_runtime_scan_patterns) do
    for _, path in ipairs(vim.fn.glob(pattern, false, true)) do
      add_runtime(runtimes, seen, path, { source = 'managed' })
    end
  end

  table.sort(runtimes, function(left, right)
    if left._preferred ~= right._preferred then
      return left._preferred
    end

    if left._major ~= right._major then
      return left._major < right._major
    end

    return left.path < right.path
  end)

  return runtimes
end

local function pick_default_runtime(runtimes, launcher_runtime)
  for _, runtime in ipairs(runtimes) do
    if runtime._preferred then
      return runtime
    end
  end

  if launcher_runtime then
    return launcher_runtime
  end

  if #runtimes == 1 then
    return runtimes[1]
  end

  return runtimes[#runtimes]
end

local function pick_launcher_runtime(runtimes)
  for _, runtime in ipairs(runtimes) do
    if runtime._source == 'system' and runtime._major == 17 then
      return {
        jdtls_version = '1.43.0',
        jdk_version = '17',
        runtime = runtime,
        auto_install = false,
      }
    end
  end

  for _, runtime in ipairs(runtimes) do
    if runtime._source == 'system' and runtime._major >= 21 and runtime._major <= 25 then
      return {
        jdtls_version = '1.54.0',
        jdk_version = tostring(runtime._major),
        runtime = runtime,
        auto_install = false,
      }
    end
  end

  for _, runtime in ipairs(runtimes) do
    if runtime._major == 17 then
      return {
        jdtls_version = '1.43.0',
        jdk_version = '17',
        runtime = runtime,
        auto_install = false,
      }
    end
  end

  for _, runtime in ipairs(runtimes) do
    if runtime._major >= 21 and runtime._major <= 25 then
      return {
        jdtls_version = '1.54.0',
        jdk_version = tostring(runtime._major),
        runtime = runtime,
        auto_install = false,
      }
    end
  end

  return {
    jdtls_version = '1.43.0',
    jdk_version = '17',
    runtime = nil,
    auto_install = true,
  }
end

local function get_state()
  if state then
    return state
  end

  local runtimes = detect_java_runtimes()
  local launcher = pick_launcher_runtime(runtimes)
  local default_runtime = pick_default_runtime(runtimes, launcher.runtime)
  if default_runtime then
    default_runtime.default = true
  end

  state = {
    runtimes = runtimes,
    default_runtime = default_runtime,
    launcher = launcher,
    projects = {},
  }

  return state
end

local function project_root(path_or_bufnr)
  local path
  if type(path_or_bufnr) == 'string' then
    path = path_or_bufnr
  elseif type(path_or_bufnr) == 'number' then
    path = vim.api.nvim_buf_get_name(path_or_bufnr)
  else
    path = vim.api.nvim_buf_get_name(0)
  end

  if not path or path == '' then
    path = vim.fn.getcwd()
  end

  path = vim.fs.normalize(path)

  local java_markers = {
    'pom.xml',
    'mvnw',
    'build.gradle',
    'build.gradle.kts',
    'settings.gradle',
    'settings.gradle.kts',
    'gradlew',
  }

  local initial_cwd = _G.initial_cwd or vim.fn.getcwd()
  initial_cwd = vim.fs.normalize(initial_cwd)

  -- Check if initial_cwd is a java project
  local initial_cwd_is_java = false
  for _, marker in ipairs(java_markers) do
    if vim.fn.filereadable(vim.fs.joinpath(initial_cwd, marker)) == 1 then
      initial_cwd_is_java = true
      break
    end
  end

  if initial_cwd_is_java then
    -- If the path is under initial_cwd, or is a system temporary file (like autostart),
    -- we treat initial_cwd as the project root.
    local is_inside = path:sub(1, #initial_cwd) == initial_cwd
    local is_temp = path:match('^/tmp/') or path:match('^/private/var/') or path:match('^/var/')
    if is_inside or is_temp then
      return initial_cwd
    end
  end

  local java_root = vim.fs.root(path, java_markers)
  if java_root then
    return java_root
  end

  return project.root(path_or_bufnr)
end

function M.patch_jdtls_workspace_path()
  local ok, lsp_utils = pcall(require, 'java-core.utils.lsp')
  if not ok or lsp_utils._user_pid_workspace_patch then
    return
  end

  local original = lsp_utils.get_jdtls_cache_data_path
  lsp_utils.get_jdtls_cache_data_path = function(cwd)
    local base = original(cwd)
    return vim.fs.joinpath(base, 'nvim-' .. tostring(vim.fn.getpid()))
  end
  lsp_utils._user_pid_workspace_patch = true
end

local function is_java_project_root(root)
  if not root or root == '' then
    return false
  end
  for _, marker in ipairs({
    'pom.xml',
    'mvnw',
    'build.gradle',
    'build.gradle.kts',
    'settings.gradle',
    'settings.gradle.kts',
    'gradlew',
  }) do
    if is_file(vim.fs.joinpath(root, marker)) then
      return true
    end
  end
  return false
end

local function first_java_file(root)
  for _, candidate_root in ipairs({
    vim.fs.joinpath(root, 'src', 'main', 'java'),
    vim.fs.joinpath(root, 'src', 'test', 'java'),
    root,
  }) do
    if is_dir(candidate_root) then
      local matches = vim.fs.find(function(name)
        return name:match('%.java$') ~= nil
      end, {
        path = candidate_root,
        type = 'file',
        limit = 1,
      })
      if #matches > 0 then
        return vim.fs.normalize(matches[1])
      end
    end
  end
end

local function client_root(client)
  if client.config and client.config.root_dir and client.config.root_dir ~= '' then
    return vim.fs.normalize(client.config.root_dir)
  end
  if client.workspace_folders and client.workspace_folders[1] and client.workspace_folders[1].uri then
    return vim.fs.normalize(vim.uri_to_fname(client.workspace_folders[1].uri))
  end
end

local function jdtls_client_for_root(root)
  local normalized_root = vim.fs.normalize(root)
  for _, client in ipairs(vim.lsp.get_clients({ name = 'jdtls' })) do
    if client_root(client) == normalized_root then
      return client
    end
  end
end

local function java_buffer_for_root(root)
  local normalized_root = vim.fs.normalize(root)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == '' then
      local path = vim.api.nvim_buf_get_name(bufnr)
      if path ~= '' and path:sub(-5) == '.java' and project_root(path) == normalized_root then
        return bufnr
      end
    end
  end
end

function M.ensure_project_jdtls(root, opts)
  opts = opts or {}
  root = vim.fs.normalize(root or vim.fn.getcwd())
  if not is_java_project_root(root) then
    return false
  end
  if jdtls_client_for_root(root) then
    return true
  end

  local current = get_state()
  local project_state = current.projects[root] or {}
  current.projects[root] = project_state

  local existing_java_bufnr = java_buffer_for_root(root)
  if existing_java_bufnr and not opts.force then
   project_state.bufnr = existing_java_bufnr
   project_state.anchor = vim.api.nvim_buf_get_name(existing_java_bufnr)
   if not project_state.pending_retry then
     project_state.pending_retry = true
     vim.defer_fn(function()
       project_state.pending_retry = false
       if not jdtls_client_for_root(root) then
         M.ensure_project_jdtls(root, { force = true })
       end
     end, 1500)
   end
   return true
  end

  if project_state.starting then
   return false
  end

  project_state.anchor = project_state.anchor or first_java_file(root)
  if not project_state.anchor then
   return false
  end

  project_state.starting = true
  progress_echo('java-lsp: ensuring binary for ' .. project_label(root) .. '...', 'ModeMsg')
  local java_lsp_bin = M.ensure_java_lsp_installed({ force = opts.refresh_binary, notify = false })
  if not java_lsp_bin then
   project_state.starting = false
   progress_echo('java-lsp: install failed for ' .. project_label(root), 'ErrorMsg')
   return false
  end

  vim.schedule(function()
   progress_echo('java-lsp: starting ' .. project_label(root) .. '...', 'ModeMsg')
   local bufnr = existing_java_bufnr or project_state.bufnr
   if not bufnr or bufnr <= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
     bufnr = vim.fn.bufadd(project_state.anchor)
     project_state.bufnr = bufnr
   end

   vim.fn.bufload(bufnr)
   vim.bo[bufnr].bufhidden = 'hide'
   vim.bo[bufnr].buflisted = false
   if vim.bo[bufnr].filetype ~= 'java' then
     vim.bo[bufnr].filetype = 'java'
   end

   vim.api.nvim_buf_call(bufnr, function()
     vim.cmd('silent! LspStart jdtls')
   end)

   vim.defer_fn(function()
     project_state.starting = false
   end, 200)
  end)

  return true
end

local function basename(path)
  return vim.fn.fnamemodify(path, ':t')
end

local function runtime_settings_entry(runtime)
  return {
    name = runtime.name,
    path = runtime.path,
    default = runtime.default or nil,
  }
end

local function find_files_by_name(root, filename, limit)
  return vim.fs.find(function(name)
    return name == filename
  end, {
    path = root,
    type = 'file',
    limit = limit or 50,
  })
end

local function java_fqn(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local class_name = vim.fn.fnamemodify(name, ':t:r')
  if class_name == '' then
    return nil
  end

  local max_lines = math.min(vim.api.nvim_buf_line_count(bufnr), 200)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, max_lines, false)) do
    local package_name = line:match('^%s*package%s+([%w_%.]+)%s*;')
    if package_name then
      return package_name .. '.' .. class_name
    end
  end

  return class_name
end

local function java_fqn_from_file(path)
  local class_name = vim.fn.fnamemodify(path, ':t:r')
  if class_name == '' then
    return nil
  end

  for _, line in ipairs(read_file_lines(path)) do
    local package_name = line:match('^%s*package%s+([%w_%.]+)%s*;')
    if package_name then
      return package_name .. '.' .. class_name
    end
  end

  return class_name
end

local function mapper_namespace_from_file(path)
  for _, line in ipairs(read_file_lines(path)) do
    local namespace = line:match('<mapper.-namespace%s*=%s*"([^"]+)"')
    if namespace then
      return namespace
    end
  end
end

local function xml_statement_id(bufnr)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local statement_tags = {
    select = true,
    insert = true,
    update = true,
    delete = true,
    sql = true,
  }

  for start_line = cursor_line, 1, -1 do
    local tag_name = lines[start_line]:match('<%s*([%w:_-]+)')
    if tag_name and statement_tags[tag_name] then
      local tag_text = lines[start_line]
      local end_line = start_line

      while end_line < #lines and not tag_text:find('>', 1, true) do
        end_line = end_line + 1
        tag_text = tag_text .. '\n' .. lines[end_line]
      end

      local statement_id = tag_text:match('id%s*=%s*"([^"]+)"')
      if statement_id then
        return statement_id
      end
    end
  end
end

local function java_method_name(bufnr)
  local line = vim.api.nvim_get_current_line()
  local class_name = basename(vim.api.nvim_buf_get_name(bufnr)):gsub('%.java$', '')

  for name in line:gmatch('([%w_]+)%s*%(') do
    if name ~= class_name then
      return name
    end
  end

  local cword = vim.fn.expand('<cword>')
  if cword ~= '' and line:match(vim.pesc(cword) .. '%s*%(') then
    return cword
  end
end

local function find_java_line(path, method_name)
  if not method_name or method_name == '' then
    return 1
  end

  local pattern = '%f[%w_]' .. vim.pesc(method_name) .. '%s*%('
  for index, line in ipairs(read_file_lines(path)) do
    if line:match(pattern) then
      return index
    end
  end

  return 1
end

local function find_xml_line(path, statement_id)
  if not statement_id or statement_id == '' then
    return 1
  end

  local escaped = vim.pesc(statement_id)
  for index, line in ipairs(read_file_lines(path)) do
    if line:match('id%s*=%s*"' .. escaped .. '"') then
      return index
    end
  end

  return 1
end



function M.java_setup_config()
  local current = get_state()
  local enable_spring_boot = false
  if vim.g.enable_spring_boot_tools ~= nil then
    enable_spring_boot = vim.g.enable_spring_boot_tools
  end
  return {
    jdtls = {
      version = current.launcher.jdtls_version,
    },
    jdk = {
      auto_install = current.launcher.auto_install,
      version = current.launcher.jdk_version,
    },
    lombok = {
      enable = true,
    },
    spring_boot_tools = {
      enable = enable_spring_boot,
    },
  }
end

function M.jdtls_config(base_settings)
  local current = get_state()
  local settings = vim.deepcopy(base_settings or {})
  local maven_settings = vim.fs.joinpath(vim.fn.expand('~'), '.m2', 'settings.xml')
  settings = vim.tbl_deep_extend('force', settings, {
    java = {
      configuration = {},
    },
  })

  if #current.runtimes > 0 then
    settings.java.configuration.runtimes = vim.tbl_map(runtime_settings_entry, current.runtimes)
  end

  if is_file(maven_settings) then
    settings.java.import = settings.java.import or {}
    settings.java.import.maven = settings.java.import.maven or {}
    settings.java.import.maven.userSettings = maven_settings
  end

  local config = {
    settings = settings,
  }

  if current.launcher.runtime then
    config.cmd_env = {
      JAVA_HOME = current.launcher.runtime.path,
      PATH = current.launcher.runtime.path .. '/bin:' .. (vim.env.PATH or ''),
    }
  end

  return config
end

function M.java_lsp_bin_path()
  return java_lsp_bin_path
end

function M.java_lsp_storage_path(root)
  return vim.fs.joinpath(
    vim.fn.stdpath('data'),
    'jdtls-workspace',
    storage_project_key(root),
    'nvim-' .. tostring(vim.fn.getpid()),
    'index'
  )
end

function M.ensure_java_lsp_installed(opts)
  opts = opts or {}
  if not opts.force and vim.fn.executable(java_lsp_bin_path) == 1 then
    return java_lsp_bin_path
  end

  return install_java_lsp(opts)
end

function M.jump_mapper_pair(open_cmd)
  require('mybatis-xml.jump.mapper_pair').jump_mapper_pair(open_cmd)
end

function M.is_mapper_buffer(bufnr)
  return require('mybatis-xml.jump.mapper_pair').is_mapper_buffer(bufnr)
end

function M.attach_mapper_keymaps(bufnr)
  require('mybatis-xml.jump.mapper_pair').attach_mapper_keymaps(bufnr)
end

function M.resolve_mapper_xml(bufnr)
  return require('mybatis-xml.jump.mapper_pair').resolve_mapper_xml(bufnr)
end

function M.resolve_mapper_java(bufnr)
  return require('mybatis-xml.jump.mapper_pair').resolve_mapper_java(bufnr)
end

function M.setup()
  M.patch_jdtls_workspace_path()

  local ok_jdtls, jdtls_ui = pcall(require, 'jdtls.ui')
  if ok_jdtls and not jdtls_ui._user_pick_many_patched then
    local original_pick_many = jdtls_ui.pick_many
    local select_mod = require('user.select')
    jdtls_ui.pick_many = function(items, prompt, label_f, opts)
      local co = coroutine.running()
      if co then
        select_mod.select_many(items, prompt, label_f, opts, function(selected)
          coroutine.resume(co, selected)
        end)
        return coroutine.yield()
      else
        return original_pick_many(items, prompt, label_f, opts)
      end
    end
    jdtls_ui._user_pick_many_patched = true
  end

  local group = vim.api.nvim_create_augroup('UserJavaMapper', { clear = true })
  local startup_group = vim.api.nvim_create_augroup('UserJavaAutostart', { clear = true })

  vim.api.nvim_create_user_command('MapperSwitch', function(opts)
    M.jump_mapper_pair(opts.bang and 'vsplit' or 'edit')
  end, {
    bang = true,
    desc = 'Jump between Mapper.java and Mapper.xml',
  })

  vim.api.nvim_create_user_command('JavaLspInstall', function()
    M.ensure_java_lsp_installed({ force = true })
  end, {
    desc = 'Install java-lsp with go install',
  })

  vim.api.nvim_create_autocmd({ 'BufEnter', 'FileType' }, {
    group = group,
    pattern = '*',
    callback = function(args)
      M.attach_mapper_keymaps(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ 'VimEnter', 'DirChanged' }, {
    group = startup_group,
    callback = function()
      vim.defer_fn(function()
        M.ensure_project_jdtls(vim.fn.getcwd())
      end, 100)
    end,
  })

  vim.api.nvim_create_autocmd('BufEnter', {
    group = startup_group,
    callback = function(args)
      local name = vim.api.nvim_buf_get_name(args.buf)
      if name == '' or vim.bo[args.buf].filetype ~= 'java' then
        return
      end
      local root = project_root(args.buf)
      local current = get_state()
      local project_state = current.projects[root]
      if project_state then
        project_state.bufnr = args.buf
        project_state.anchor = name
      end
      M.ensure_project_jdtls(root)
    end,
  })

  vim.api.nvim_create_autocmd('LspDetach', {
    group = startup_group,
    callback = function(args)
      local client_id = args.data and args.data.client_id or nil
      local client = client_id and vim.lsp.get_client_by_id(client_id) or nil
      if client and client.name ~= 'jdtls' then
        return
      end
      local root = client and client_root(client) or project_root(args.buf)
      if not root or not is_java_project_root(root) then
        return
      end
      vim.defer_fn(function()
        if not jdtls_client_for_root(root) then
          M.ensure_project_jdtls(root, { force = true })
        end
      end, 300)
    end,
  })

  vim.api.nvim_create_autocmd('LspAttach', {
    group = startup_group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data and args.data.client_id or -1)
      if not client or client.name ~= 'jdtls' then
        return
      end
      local root = client_root(client)
      if not root or not is_java_project_root(root) then
        return
      end
      progress_echo('java-lsp: ready for ' .. project_label(root), 'ModeMsg')
    end,
  })
end

M._test = {
  project_root = project_root,
  java_lsp_storage_path = M.java_lsp_storage_path,
  get_tag_type = function(...) return require('mybatis-xml.jump.mapper_pair')._test.get_tag_type(...) end,
  get_method_return_type = function(...) return require('mybatis-xml.jump.mapper_pair')._test.get_method_return_type(...) end,
  resolve_mapper_xml = M.resolve_mapper_xml,
  resolve_mapper_java = M.resolve_mapper_java,
  java_fqn = function(...) return require('mybatis-xml.jump.mapper_pair')._test.java_fqn(...) end,
  java_fqn_from_file = function(...) return require('mybatis-xml.jump.mapper_pair')._test.java_fqn_from_file(...) end,
  xml_statement_id = function(...) return require('mybatis-xml.jump.mapper_pair')._test.xml_statement_id(...) end,
  is_mapper_java_buffer = function(...) return require('mybatis-xml.jump.mapper_pair')._test.is_mapper_java_buffer(...) end,
  is_mapper_xml_buffer = function(...) return require('mybatis-xml.jump.mapper_pair')._test.is_mapper_xml_buffer(...) end,
  find_java_line = function(...) return require('mybatis-xml.jump.mapper_pair')._test.find_java_line(...) end,
  find_xml_line = function(...) return require('mybatis-xml.jump.mapper_pair')._test.find_xml_line(...) end,
  java_method_name = function(...) return require('mybatis-xml.jump.mapper_pair')._test.java_method_name(...) end,
}

return M
