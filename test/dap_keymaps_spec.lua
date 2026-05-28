local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

package.loaded['user.dap_keymaps'] = nil

local original_dap = package.loaded['dap']
local original_notify = vim.notify
local notifications = {}

package.loaded['dap'] = {
  listeners = {
    after = {
      event_stopped = {},
    },
    before = {
      event_continued = {},
      event_exited = {},
      event_terminated = {},
      disconnect = {},
    },
  },
  step_over = function() end,
  step_into = function() end,
  step_out = function() end,
  continue = function() end,
  toggle_breakpoint = function() end,
}

vim.notify = function(message)
  table.insert(notifications, tostring(message))
end

local dap_keymaps = require('user.dap_keymaps')
dap_keymaps.setup()
dap_keymaps.ensure_listeners()

local function has_buffer_map(lhs)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, 'n')) do
    if map.lhs == lhs then
      return true
    end
  end
  return false
end

support.expect_true('dap quick mode starts disabled', not dap_keymaps.is_quick_mode())
package.loaded['dap'].listeners.after.event_stopped.user_dap_quick_mode()
vim.wait(100)

support.expect_true('dap quick mode enters on stop', dap_keymaps.is_quick_mode())
support.expect_true('dap quick mode maps n', has_buffer_map('n'))
support.expect_true('dap quick mode maps c', has_buffer_map('c'))
support.expect_true('dap quick mode notifies on enter', notifications[#notifications] == 'DAP quick mode on')

package.loaded['dap'].listeners.before.event_continued.user_dap_quick_mode()
vim.wait(100)

support.expect_true('dap quick mode exits on continue', not dap_keymaps.is_quick_mode())
support.expect_true('dap quick mode unmaps n', not has_buffer_map('n'))
support.expect_true('dap quick mode notifies on exit', notifications[#notifications] == 'DAP quick mode off')

vim.notify = original_notify
package.loaded['dap'] = original_dap
support.flush()
