-- Minimal and standard DAP + DAP UI setup
-- Replaces old telemetry and complex project loaders with original DAP features.

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
  vim.fn.sign_define("DapBreakpointCondition", { text = "🟡", texthl = "DapBreakpointCondition", linehl = "", numhl = "" })
  vim.fn.sign_define("DapStopped", { text = "➡️", texthl = "DapStopped", linehl = "DebugStoppedLine", numhl = "DebugStoppedLine" })

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
    dap.continue()
  end, { desc = 'Start or continue debugging session' })

  vim.api.nvim_create_user_command('DapAttach', function(opts)
    local arg = vim.trim(opts.args or '')
    local filetype = vim.bo.filetype

    if filetype == 'java' or arg ~= '' then
      -- Java Port Attach
      local port = tonumber(arg) or 5005
      local config = {
        name = "Java Attach (Port " .. port .. ")",
        type = "java",
        request = "attach",
        hostName = "127.0.0.1",
        port = port,
      }
      vim.notify("Attaching Java debugger to port " .. port .. "...", vim.log.levels.INFO)
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
end

return M
