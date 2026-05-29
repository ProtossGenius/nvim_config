-- [[ user.audit ]]
-- Audit logging for plugins, keymaps, and DAP actions/events.

local M = {}

local AUDIT_LOG_PATH = vim.fs.normalize(vim.fn.stdpath('state') .. '/user-audit.log')
local DAP_LOG_PATH = vim.fs.normalize(vim.fn.stdpath('state') .. '/user-dap.log')

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

local function format_context(details)
  if not details then
    return '{}'
  end
  local ok, json = pcall(vim.json.encode, details)
  if ok then
    return json
  end
  return vim.inspect(details):gsub('%s+', ' ')
end

function M.log_dap_action(message, context)
  local time = os.date('%Y-%m-%d %H:%M:%S')
  local level = 'INFO'
  local msg_lower = tostring(message):lower()
  if msg_lower:find('warn') or msg_lower:find('fail') or msg_lower:find('terminated') or msg_lower:find('exited') or msg_lower:find('abort') or msg_lower:find('blocked') or msg_lower:find('error') then
    level = 'WARN'
  end
  local context_str = format_context(context)
  local line = string.format('%s [%s] %s %s', time, level, tostring(message), context_str)
  append_to_file(DAP_LOG_PATH, line)
  append_to_file(AUDIT_LOG_PATH, line)
end

function M.log_dap_event(event, body)
  M.log_dap_action('DAP event: ' .. tostring(event), body)
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
