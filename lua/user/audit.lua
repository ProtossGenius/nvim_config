-- [[ user.audit ]]
-- Audit logging for plugins, keymaps, and DAP actions/events.

local M = {}

local AUDIT_LOG_PATH = vim.fs.normalize(vim.fn.stdpath('state') .. '/user-audit.log')
local DAP_LOG_PATH = vim.fs.normalize(vim.fn.stdpath('state') .. '/user-dap-actions.log')

local is_headless_cached = false

local function should_log()
  return not is_headless_cached
end

local function append_to_file(path, line)
  if not should_log() then
    return
  end
  local f = io.open(path, 'a')
  if f then
    f:write(line .. '\n')
    f:close()
  end
end

function M.log_keymap(mode, lhs, desc)
  local time = os.date('%Y-%m-%dT%H:%M:%S')
  local line = string.format('[%s] KEYMAP: mode=%s, key=%s, desc=%s', time, tostring(mode), tostring(lhs), tostring(desc or ''))
  append_to_file(AUDIT_LOG_PATH, line)
end

function M.log_module_load(modname)
  local time = os.date('%Y-%m-%dT%H:%M:%S')
  local line = string.format('[%s] MODULE_LOAD: %s', time, tostring(modname))
  append_to_file(AUDIT_LOG_PATH, line)
end

function M.log_dap_action(action, details)
  local time = os.date('%Y-%m-%dT%H:%M:%S')
  local details_str = details and vim.inspect(details):gsub('%s+', ' ') or ''
  local line = string.format('[%s] DAP_ACTION: %s %s', time, tostring(action), details_str)
  append_to_file(DAP_LOG_PATH, line)
  append_to_file(AUDIT_LOG_PATH, line)
end

function M.log_dap_event(event, body)
  local time = os.date('%Y-%m-%dT%H:%M:%S')
  local body_str = body and vim.inspect(body):gsub('%s+', ' ') or ''
  local line = string.format('[%s] DAP_EVENT: %s %s', time, tostring(event), body_str)
  append_to_file(DAP_LOG_PATH, line)
end

function M.setup()
  -- Cache headless status safely on startup
  local ok, uis = pcall(vim.api.nvim_list_uis)
  if ok and #uis == 0 then
    is_headless_cached = true
  end

  -- 1. Intercept all vim.keymap.set calls to log their execution
  local original_set = vim.keymap.set
  vim.keymap.set = function(mode, lhs, rhs, opts)
    opts = opts or {}
    local desc = opts.desc or ''
    local wrapped_rhs = rhs

    if type(rhs) == 'function' then
      wrapped_rhs = function(...)
        M.log_keymap(mode, lhs, desc)
        return rhs(...)
      end
    elseif type(rhs) == 'string' then
      if opts.expr then
        wrapped_rhs = function()
          M.log_keymap(mode, lhs, desc ~= '' and desc or rhs)
          local ok_eval, res = pcall(vim.api.nvim_eval, rhs)
          if ok_eval then
            return res
          end
          return rhs
        end
      else
        wrapped_rhs = function()
          M.log_keymap(mode, lhs, desc ~= '' and desc or rhs)
          local keys = vim.api.nvim_replace_termcodes(rhs, true, true, true)
          vim.api.nvim_feedkeys(keys, 'm', true)
        end
      end
    end

    original_set(mode, lhs, wrapped_rhs, opts)
  end

  -- 2. Intercept global require to log module load events
  local loaded_modules = {}
  local original_require = require
  _G.require = function(modname)
    if should_log() and not loaded_modules[modname] and not package.loaded[modname] then
      loaded_modules[modname] = true
      M.log_module_load(modname)
    end
    return original_require(modname)
  end
end

return M
