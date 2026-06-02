local function kill_project_debuggee_processes()
  local project = require('user.project')
  local root = project.root()
  if not root or root == '' then return end
  local project_name = vim.fs.basename(root)
  local my_pid = vim.fn.getpid()

  local handle = io.popen("ps -efww | grep java")
  if not handle then return end
  local output = handle:read("*all")
  handle:close()

  for line in output:gmatch("[^\r\n]+") do
    if line:find("-agentlib:jdwp=transport=dt_socket", 1, true) 
       and line:find(project_name, 1, true)
       and line:find("bin/java", 1, true) then
      local pid = line:match("^%s*%d+%s+(%d+)") or line:match("^%s*(%d+)")
      if pid then
        pid = tonumber(pid)
        if pid and pid > 0 and pid ~= my_pid then
          vim.fn.system("kill -9 " .. pid)
        end
      end
    end
  end
end

local M = {}

function M.setup()
  local dap = require('dap')
  local dapui = require('dapui')

  -- 1. Initialize DAP UI
  dapui.setup()

  -- 2. Configure auto-open/close listeners for DAP UI
  dap.listeners.after.event_initialized["dapui_config"] = function()
    dapui.open()
  end
  dap.listeners.before.event_terminated["dapui_config"] = function()
    dapui.close()
  end
  dap.listeners.before.event_exited["dapui_config"] = function()
    dapui.close()
  end

  -- 3. Configure Visual Signs
  vim.fn.sign_define("DapBreakpoint", { text = "🔴", texthl = "DapBreakpoint", linehl = "", numhl = "" })
  vim.fn.sign_define("DapBreakpointCondition", { text = "🔶", texthl = "DapBreakpointCondition", linehl = "", numhl = "" })
  vim.fn.sign_define("DapBreakpointRejected", { text = "🚫", texthl = "DapBreakpointRejected", linehl = "", numhl = "" })
  vim.fn.sign_define("DapLogPoint", { text = "💬", texthl = "DapLogPoint", linehl = "", numhl = "" })
  vim.fn.sign_define("DapStopped", { text = "➡️", texthl = "DapStopped", linehl = "DebugStoppedLine", numhl = "DebugStoppedLine" })

  -- Setup highlight colors for DAP signs
  vim.api.nvim_set_hl(0, "DapBreakpoint", { fg = "#e06c75", bg = "" })
  vim.api.nvim_set_hl(0, "DapBreakpointCondition", { fg = "#e5c07b", bg = "" })
  vim.api.nvim_set_hl(0, "DapBreakpointRejected", { fg = "#5c6370", bg = "" })
  vim.api.nvim_set_hl(0, "DapLogPoint", { fg = "#61afef", bg = "" })

  -- Highlight the current debug line
  vim.api.nvim_set_hl(0, "DebugStoppedLine", { ctermbg = 0, bg = "#3b4252", bold = true })

  -- 4. Locate and configure C++ Adapter (lldb-dap)
  local lldb_bin = vim.fn.exepath('lldb-dap')
  if lldb_bin == '' and vim.fn.executable('xcrun') == 1 then
    local output = vim.fn.system('xcrun --find lldb-dap')
    if vim.v.shell_error == 0 then
      lldb_bin = vim.trim(output)
    end
  end

  if lldb_bin ~= '' then
    dap.adapters.lldb = {
      type = 'executable',
      command = lldb_bin,
      name = 'lldb',
    }
  end

  -- 5. Define Native Commands
  vim.api.nvim_create_user_command('DapLaunch', function()
    require('dap').continue()
  end, { desc = 'Start or continue debugging session' })

  vim.api.nvim_create_user_command('DapTerminate', function()
    local dap = require('dap')
    local dapui = require('dapui')
    local session = dap.session()
    if session then
      if session.config and session.config.request == "attach" then
        pcall(dap.disconnect, { terminateDebuggee = false })
      else
        pcall(dap.disconnect, { terminateDebuggee = true })
        pcall(dap.close)
        pcall(kill_project_debuggee_processes)
      end
    else
      pcall(dap.terminate)
      pcall(kill_project_debuggee_processes)
    end
    pcall(dapui.close)
  end, { desc = 'Terminate active debugging session' })

  vim.api.nvim_create_user_command('DapAttach', function(opts)
    local dap = require('dap')
    local arg = vim.trim(opts.args or '')
    local filetype = vim.bo.filetype

    if filetype == 'java' or arg ~= '' then
      -- Java Port Attach
      local port
      if arg ~= '' then
        port = tonumber(arg)
        if not port or port ~= math.floor(port) or port < 1 or port > 65535 then
          vim.notify('DapAttach expects a TCP port, for example :DapAttach 5005', vim.log.levels.WARN)
          return
        end
      else
        -- Try to resolve from project root .dap_attach file
        local project = require('user.project')
        local root = project.root()
        if root and root ~= '' then
          local filepath = vim.fs.joinpath(root, '.dap_attach')
          local f = io.open(filepath, 'r')
          if f then
            local content = f:read('*all')
            f:close()
            port = tonumber(vim.trim(content or ''))
          end
        end
      end
      port = port or 5005

      local config = {
        name = "Java Attach (Port " .. port .. ")",
        type = "java",
        request = "attach",
        hostName = "127.0.0.1",
        port = port,
      }
      dap.run(config)
    elseif filetype == 'c' or filetype == 'cpp' then
      -- C/C++ Process ID Attach
      vim.ui.input({ prompt = 'Enter Process ID (PID) to attach: ' }, function(pid_str)
        local pid = tonumber(vim.trim(pid_str or ''))
        if pid then
          local config = {
            name = "C++ Attach (PID " .. pid .. ")",
            type = "lldb",
            request = "attach",
            pid = pid,
          }
          vim.notify("Attaching C++ debugger to PID " .. pid .. "...", vim.log.levels.INFO)
          dap.run(config)
        else
          vim.notify("Attach aborted: Invalid or missing PID", vim.log.levels.WARN)
        end
      end)
    else
      vim.notify("DapAttach failed: Unsupported filetype or active debugging profile.", vim.log.levels.WARN)
    end
  end, {
    nargs = '?',
    desc = 'Attach debugger (Java TCP port, or C/C++ PID)',
  })

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
    require('dap').toggle_breakpoint()
  end, {
    desc = 'Toggle a DAP breakpoint on the current line',
  })
end

local function is_config_file(path)
  return path and path ~= '' and vim.fs.basename(path) == '.nvim-dap.json'
end

local function source_context_buf(path_or_bufnr)
  local project = require('user.project')
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

local function config_path(path_or_bufnr)
  local project = require('user.project')
  local path = project.path_from_buf(path_or_bufnr or 0) or ''
  local root = project.root(path)
  return vim.fs.joinpath(root, '.nvim-dap.json')
end

local function placeholder_vars(path_or_bufnr)
  local project = require('user.project')
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

local function starts_with_path(path, root)
  return path == root or path:sub(1, #root + 1) == root .. '/'
end

local function find_jdtls_client(path)
  local best_client
  local best_root_len = -1

  local clients = vim.lsp.get_clients({ name = 'jdtls' })
  if path:match('^jdt:/') and #clients > 0 then
    return clients[1]
  end

  for _, client in ipairs(clients) do
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
  local project = require('user.project')
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
  local project = require('user.project')
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

local function pick_process(query, callback)
  local cmd = { 'ps', '-axo', 'pid=,command=' }
  local ok, proc = pcall(vim.system, cmd, { text = true })
  if not ok or not proc then
    callback(nil)
    return
  end

  local result = proc:wait()
  if result.code ~= 0 then
    vim.notify('ps command failed: ' .. (result.stderr or ''), vim.log.levels.ERROR)
    callback(nil)
    return
  end

  local stdout = result.stdout or ''
  local matches = {}
  for line in stdout:gmatch('[^\r\n]+') do
    if line:find(query, 1, true) and not line:find('grep', 1, true) then
      local pid, command = line:match('^%s*(%d+)%s+(.+)$')
      if pid then
        table.insert(matches, { pid = tonumber(pid), command = command })
      end
    end
  end

  if #matches == 0 then
    vim.notify('No processes found matching query: ' .. query, vim.log.levels.WARN)
    callback(nil)
  elseif #matches == 1 then
    callback(matches[1].pid)
  else
    local items = {}
    for _, match in ipairs(matches) do
      table.insert(items, string.format('%d: %s', match.pid, match.command))
    end
    vim.ui.select(items, { prompt = 'Select process to attach' }, function(choice, idx)
      if not choice then
        callback(nil)
        return
      end
      local pid = tonumber(choice:match('^(%d+):'))
      if pid then
        callback(pid)
      else
        callback(nil)
      end
    end)
  end
end

function M.edit_config(path_or_bufnr)
  local project = require('user.project')
  local path = project.path_from_buf(path_or_bufnr or 0) or ''
  local root = project.root(path)
  local file = vim.fs.joinpath(root, '.nvim-dap.json')

  local data
  local cmake_file = vim.fs.joinpath(root, 'CMakeLists.txt')
  local pom_file = vim.fs.joinpath(root, 'pom.xml')

  if vim.fn.filereadable(cmake_file) == 1 then
    local content = table.concat(vim.fn.readfile(cmake_file), '\n')
    local project_name = content:match('project%s*%(%s*([%w_-]+)%s*%)') or 'app'

    data = {
      _desc = 'Default launch + attach configs generated from CMakeLists.txt.',
      _detected = {
        cmake = {
          projectName = project_name
        },
        buildTool = 'cmake'
      },
      configurations = {
        {
          name = 'Launch app',
          type = 'lldb',
          request = 'launch',
          program = '${projectRoot}/build/' .. project_name,
          cwd = '${projectRoot}'
        },
        {
          name = 'attach-process',
          type = 'lldb',
          request = 'attach',
          processQuery = project_name
        }
      }
    }
  else
    local name = 'temp-eclipse-project'
    local project_file = vim.fs.joinpath(root, '.project')
    if vim.fn.filereadable(project_file) == 1 then
      local content = table.concat(vim.fn.readfile(project_file), '\n')
      name = content:match('<name>%s*(.-)%s*</name>') or name
    end

    local artifact_id = 'temp-artifact'
    if vim.fn.filereadable(pom_file) == 1 then
      local content = table.concat(vim.fn.readfile(pom_file), '\n')
      artifact_id = content:match('<artifactId>%s*(.-)%s*</artifactId>') or artifact_id
    end

    data = {
      _desc = 'Default launch + port configs generated from the current build files.',
      _detected = {
        maven = {
          artifactId = artifact_id
        },
        eclipse = {
          projectName = name
        },
        buildTool = 'maven'
      },
      configurations = {
        {
          name = 'Attach port',
          type = 'java',
          request = 'attach',
          hostName = '127.0.0.1',
          port = 5005,
          mainClass = 'com.example.Main',
          stepFilters = {
            skipClasses = { '$JDK', 'org.junit.*' }
          }
        },
        {
          name = 'Launch app',
          type = 'java',
          request = 'launch',
          mainClass = 'com.example.Main',
          stepFilters = {
            skipClasses = { '$JDK', 'org.junit.*', 'org.springframework.*' }
          }
        }
      }
    }
  end

  local encoded = vim.json.encode(data)
  local formatted = vim.fn.system({ 'python3', '-m', 'json.tool' }, encoded)
  if vim.v.shell_error ~= 0 then
    formatted = encoded
  end
  vim.fn.writefile(vim.split(formatted, '\n', { plain = true }), file)
end

function M.start(path_or_bufnr)
  local file = config_path(path_or_bufnr)
  if vim.fn.filereadable(file) == 0 then
    vim.notify('No debug configurations found in ' .. file, vim.log.levels.WARN)
    return
  end

  local content = table.concat(vim.fn.readfile(file), '\n')
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= 'table' or not data.configurations or #data.configurations == 0 then
    vim.notify('Invalid or empty debug configurations in ' .. file, vim.log.levels.WARN)
    return
  end

  local configurations = data.configurations
  local vars = placeholder_vars(path_or_bufnr)
  local expanded = expand_placeholders(configurations[1], vars)

  if expanded.type == 'java' and not prepare_java_dap(path_or_bufnr) then
    return
  end

  if expanded.request == 'attach' and expanded.type == 'lldb' and expanded.processQuery and not expanded.pid then
    pick_process(expanded.processQuery, function(pid)
      if not pid then
        return
      end
      expanded.pid = pid
      expanded.processQuery = nil
      local dap = require('dap')
      dap.run(expanded)
    end)
    return
  end

  local dap = require('dap')
  dap.run(expanded)
end

return M
