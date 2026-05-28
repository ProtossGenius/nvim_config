local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

package.loaded['user.dap_ui'] = nil

local original_dap = package.loaded['dap']
local original_notify = vim.notify
local notifications = {}
local requests = {}
local stacktrace_calls = 0

local dap_stub = {
  listeners = {
    after = {
      event_output = {},
      event_stopped = {},
    },
    before = {
      event_continued = {},
      event_exited = {},
      event_terminated = {},
    },
  },
}

dap_stub._session = {
  request = function(_, command, args, callback)
    table.insert(requests, { command = command, args = args })
    if command == 'stackTrace' then
      stacktrace_calls = stacktrace_calls + 1
      local source = stacktrace_calls == 1 and '/external/lib.cpp' or '/repo/src/main.cpp'
      callback(nil, {
        stackFrames = {
          {
            id = 11,
            line = 5,
            source = { path = source },
          },
        },
      })
      return
    end
    if command == 'scopes' then
      callback(nil, {
        scopes = {
          {
            name = 'Locals',
            variablesReference = 21,
          },
        },
      })
      return
    end
    if command == 'variables' then
      callback(nil, {
        variables = {
          { name = 'value', value = '7' },
        },
      })
      return
    end
    if command == 'evaluate' then
      callback(nil, {
        result = '42',
      })
      return
    end
    callback(nil, {})
  end,
}

dap_stub.session = function()
  return dap_stub._session
end

dap_stub.continue = function()
  dap_stub._continued = true
end

dap_stub.step_over = function()
  dap_stub._step_over = (dap_stub._step_over or 0) + 1
end

dap_stub.step_into = function()
  dap_stub._step_into = (dap_stub._step_into or 0) + 1
end

dap_stub.step_out = function()
  dap_stub._step_out = (dap_stub._step_out or 0) + 1
end

dap_stub.toggle_breakpoint = function()
  dap_stub._toggle_breakpoint = (dap_stub._toggle_breakpoint or 0) + 1
end

package.loaded['dap'] = dap_stub

vim.notify = function(message)
  table.insert(notifications, tostring(message))
end

local ui = require('user.dap_ui')
ui.ensure_listeners()

ui.toggle_output()
support.expect_equal('dap ui output panel stays hidden without output', notifications[#notifications], 'No DAP output available.')

ui._state.project_root = '/repo'
ui.toggle_command()
ui.listeners_attached = true
package.loaded['dap'].listeners.after.event_output.user_dap_panels(nil, {
  category = 'stdout',
  output = 'hello\nworld\n',
})
vim.wait(50)
ui.toggle_output()
ui.toggle_locals()

support.expect_equal('dap ui keeps show order', table.concat(ui._state.visible_order, ','), 'command,output,locals')
support.expect_true('dap ui output panel captured stdout', table.concat(ui._state.panels.output.lines, '\n'):find('hello', 1, true) ~= nil)

ui.handle_stopped(nil, { threadId = 3 })
vim.wait(50)
ui.execute_command('display foo')
vim.wait(50)
support.expect_equal('dap ui stores display expression', ui._state.display_expressions[1], 'foo')
support.expect_true('dap ui locals render display values', table.concat(ui._state.panels.locals.lines, '\n'):find('foo = 42', 1, true) ~= nil)

stacktrace_calls = 0
ui.execute_command('s')
vim.wait(50)
ui.handle_stopped(nil, { threadId = 3 })
vim.wait(50)
local request_names = {}
for _, request in ipairs(requests) do
  table.insert(request_names, request.command)
end
local request_trace = table.concat(request_names, ',')
support.expect_true('dap ui project step issues stepIn request', request_trace:find('stepIn', 1, true) ~= nil)
support.expect_true('dap ui project step inspects stack trace', request_trace:find('stepIn,stackTrace', 1, true) ~= nil)
local step_in_count = 0
for _, name in ipairs(request_names) do
  if name == 'stepIn' then
    step_in_count = step_in_count + 1
  end
end
support.expect_true('dap ui project step retries outside project', step_in_count >= 2)

ui.execute_command('S')
support.expect_equal('dap ui raw step into bypasses project logic', package.loaded['dap']._step_into, 1)

ui.execute_command('> foo')
vim.wait(50)
support.expect_true('dap ui prints expression values', table.concat(vim.api.nvim_buf_get_lines(ui._state.panels.command.bufnr, 0, -1, false), '\n'):find('foo = 42', 1, true) ~= nil)

vim.notify = original_notify
package.loaded['dap'] = original_dap

support.flush()
