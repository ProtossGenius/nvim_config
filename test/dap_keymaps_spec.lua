local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

package.loaded['user.dap_keymaps'] = nil

local original_dap = package.loaded['dap']
local original_notify = vim.notify
local notifications = {}

package.loaded['dap'] = {
  listeners = {
    after = {
      event_initialized = {},
      event_stopped = {},
    },
    before = {
      event_continued = {},
      event_exited = {},
      event_terminated = {},
      disconnect = {},
    },
  },
  session = function()
    return package.loaded['dap']._session
  end,
  step_over = function() end,
  step_into = function()
    package.loaded['dap']._raw_step_into = (package.loaded['dap']._raw_step_into or 0) + 1
  end,
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

local function has_map(lhs)
  local info = vim.fn.maparg(lhs, 'n', false, true)
  return type(info) == 'table' and not vim.tbl_isempty(info)
end

support.expect_true('dap quick mode starts disabled', not dap_keymaps.is_quick_mode())
package.loaded['dap'].listeners.after.event_initialized.user_dap_quick_mode()
vim.wait(100)

support.expect_true('dap quick mode enters on initialize', dap_keymaps.is_quick_mode())
support.expect_true('dap quick mode maps n globally', has_map('n'))
support.expect_true('dap quick mode maps c globally', has_map('c'))
support.expect_true('dap quick mode notifies on enter', notifications[#notifications] == 'DAP quick mode on')
vim.cmd('enew')
support.expect_true('dap quick mode survives buffer switch', has_map('n'))

local calls = {}
package.loaded['dap']._session = {
  request = function(_, command, args, callback)
    table.insert(calls, { command = command, args = args })
    if command == 'stackTrace' then
      local outside = #calls == 2
      callback(nil, {
        stackFrames = {
          {
            source = {
              path = outside and '/tmp/external.cpp' or '/repo/src/main.cpp',
            },
          },
        },
      })
      return
    end
    callback(nil, {})
  end,
}

dap_keymaps.set_project_root('/repo')
package.loaded['dap'].listeners.after.event_stopped.user_dap_quick_mode(nil, { threadId = 7 })
vim.wait(100)
dap_keymaps.step_into_project()
package.loaded['dap'].listeners.after.event_stopped.user_dap_quick_mode(nil, { threadId = 7 })
vim.wait(100)
package.loaded['dap'].listeners.after.event_stopped.user_dap_quick_mode(nil, { threadId = 7 })
vim.wait(100)

support.expect_equal('dap project step issues first stepIn', calls[1].command, 'stepIn')
support.expect_equal('dap project step inspects stack frame', calls[2].command, 'stackTrace')
support.expect_equal('dap project step retries outside project', calls[3].command, 'stepIn')
support.expect_equal('dap project step rechecks stack frame', calls[4].command, 'stackTrace')

dap_keymaps.step_into_raw()
support.expect_equal('dap raw step into bypasses project skip', package.loaded['dap']._raw_step_into, 1)

package.loaded['dap'].listeners.before.event_continued.user_dap_quick_mode()
vim.wait(100)

support.expect_true('dap quick mode stays active while session continues', dap_keymaps.is_quick_mode())
support.expect_true('dap quick mode keeps n mapping during session', has_map('n'))

package.loaded['dap'].listeners.before.event_terminated.user_dap_quick_mode()
vim.wait(100)

support.expect_true('dap quick mode exits on terminate', not dap_keymaps.is_quick_mode())
support.expect_true('dap quick mode unmaps n after terminate', not has_map('n'))
support.expect_true('dap quick mode notifies on exit', notifications[#notifications] == 'DAP quick mode off')

vim.notify = original_notify
package.loaded['dap'] = original_dap
support.flush()
