local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

package.loaded['user.dap_ui'] = nil

local original_dap = package.loaded['dap']
local original_notify = vim.notify
local notifications = {}
local requests = {}
local stacktrace_calls = 0
local tmpfile = vim.fn.tempname() .. '.cpp'

local dap_stub = {
  listeners = {
    after = {
      event_output = {},
      event_stopped = {},
      event_initialized = {},
    },
    before = {
      event_stopped = {},
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
      if args and args.levels == 100 then
        callback(nil, {
          stackFrames = {
            {
              id = 21,
              name = 'external.Library.call',
              line = 88,
              source = { path = '/external/lib.cpp' },
            },
            {
              id = 22,
              name = 'com.example.demo.Service.run',
              line = 10,
              source = { path = tmpfile },
            },
          },
        })
        return
      end

      stacktrace_calls = stacktrace_calls + 1
      local source
      if stacktrace_calls <= 2 then
        source = '/external/lib.cpp'
      else
        source = tmpfile
      end
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
      if args and args.variablesReference == 31 then
        callback(nil, {
          variables = {
            { name = 'id', value = '1', type = 'int', variablesReference = 0 },
            { name = 'name', value = 'Neo', type = 'java.lang.String', variablesReference = 0 },
          },
        })
        return
      end
      if args and args.variablesReference == 41 then
        callback(nil, {
          variables = {
            { name = 'repo', value = 'Repo', type = 'com.example.Repo', variablesReference = 0 },
          },
        })
        return
      end
      callback(nil, {
        variables = {
          { name = 'value', value = '7', type = 'int', variablesReference = 0 },
        },
      })
      return
    end
    if command == 'evaluate' then
      if args and args.expression == 'obj' then
        callback(nil, {
          result = 'User',
          type = 'com.example.User',
          variablesReference = 31,
        })
        return
      end
      if args and args.expression == 'svc' then
        callback(nil, {
          result = 'UserService',
          type = 'com.example.demo.UserService',
          variablesReference = 41,
        })
        return
      end
      callback(nil, {
        result = '42',
        type = 'int',
        variablesReference = 0,
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
  dap_stub._continued = (dap_stub._continued or 0) + 1
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
  dap_stub._breakpoint_file = vim.api.nvim_buf_get_name(0)
  dap_stub._breakpoint_line = vim.api.nvim_win_get_cursor(0)[1]
end

package.loaded['dap'] = dap_stub

vim.notify = function(message)
  table.insert(notifications, tostring(message))
end

vim.fn.writefile(vim.fn['repeat']({ '// line' }, 40), tmpfile)
vim.cmd('edit ' .. vim.fn.fnameescape(tmpfile))
vim.api.nvim_win_set_cursor(0, { 10, 0 })

local ui = require('user.dap_ui')
ui.ensure_listeners()

ui.toggle_output()
support.expect_equal('dap ui output panel stays hidden without output', notifications[#notifications], 'No DAP output available.')

ui._state.project_root = vim.fs.normalize(vim.fn.fnamemodify(tmpfile, ':h'))
local source_win = vim.fn.bufwinid(vim.fn.bufnr(tmpfile))
package.loaded['dap'].listeners.after.event_output.user_dap_panels(nil, {
  category = 'stdout',
  output = 'hello\nworld\n',
})
vim.wait(50)
ui.toggle_output()
ui.toggle_locals()

support.expect_equal('dap ui keeps fixed panel order', table.concat(ui._state.visible_order, ','), 'locals,output')
support.expect_true('dap ui output panel captured stdout', table.concat(ui._state.panels.output.lines, '\n'):find('hello', 1, true) ~= nil)
support.expect_equal('dap ui locals panel is a normal split', vim.api.nvim_win_get_config(ui._state.panels.locals.winid).relative, '')
support.expect_equal('dap ui output panel is a normal split', vim.api.nvim_win_get_config(ui._state.panels.output.winid).relative, '')
local locals_pos = vim.api.nvim_win_get_position(ui._state.panels.locals.winid)
local output_pos = vim.api.nvim_win_get_position(ui._state.panels.output.winid)
support.expect_true('dap ui locals stays above output', locals_pos[1] < output_pos[1])

vim.api.nvim_set_current_win(ui._state.panels.output.winid)
package.loaded['dap'].listeners.before.event_stopped.user_dap_panels()
support.expect_equal('dap ui stopped event restores source window focus', vim.api.nvim_get_current_win(), source_win)

ui.handle_stopped(nil, { threadId = 3 })
vim.wait(50)

ui.open_display_add_popup()
local popup_buf = ui._state.popup.bufnr
local popup_last = vim.api.nvim_buf_line_count(popup_buf)
vim.api.nvim_buf_set_lines(popup_buf, popup_last - 1, popup_last, false, { 'obj' })
ui.submit_popup()
vim.wait(50)
support.expect_equal('dap ui stores display expression from popup', ui._state.display_expressions[1], 'obj')
local locals_text = table.concat(vim.api.nvim_buf_get_lines(ui._state.panels.locals.bufnr, 0, -1, false), '\n')
support.expect_true('dap ui locals render basic type and value without equals', locals_text:find('value <int> 7', 1, true) ~= nil)
support.expect_true('dap ui locals render display type', locals_text:find('obj <User>', 1, true) ~= nil)
support.expect_true('dap ui locals render display value', locals_text:find('"id":', 1, true) ~= nil)
support.expect_true('dap ui display popup shows type', table.concat(vim.api.nvim_buf_get_lines(ui._state.popup.bufnr, 0, -1, false), '\n'):find('Type: com.example.User', 1, true) ~= nil)

ui.open_display_list()
support.expect_equal('dap ui display list popup kind', ui._state.popup.kind, 'display_list')
support.expect_true('dap ui display list shows typed json value', ui._state.popup.items[1] ~= nil and ui._state.popup.items[1].info.type == 'com.example.User')
ui.delete_selected_display()
vim.wait(50)
support.expect_equal('dap ui display delete removes expression', #ui._state.display_expressions, 0)

ui.open_eval_popup()
popup_buf = ui._state.popup.bufnr
popup_last = vim.api.nvim_buf_line_count(popup_buf)
vim.api.nvim_buf_set_lines(popup_buf, popup_last - 1, popup_last, false, { 'obj' })
ui.submit_popup()
vim.wait(50)
local eval_text = table.concat(vim.api.nvim_buf_get_lines(ui._state.popup.bufnr, 0, -1, false), '\n')
support.expect_true('dap ui eval popup shows type', eval_text:find('Type: com.example.User', 1, true) ~= nil)
support.expect_true('dap ui eval popup shows json value', eval_text:find('"name": "Neo"', 1, true) ~= nil)
popup_last = vim.api.nvim_buf_line_count(ui._state.popup.bufnr)
vim.api.nvim_buf_set_lines(ui._state.popup.bufnr, popup_last - 1, popup_last, false, { 'svc' })
ui.submit_popup()
vim.wait(50)
eval_text = table.concat(vim.api.nvim_buf_get_lines(ui._state.popup.bufnr, 0, -1, false), '\n')
support.expect_true('dap ui service object shows type in eval', eval_text:find('Type: com.example.demo.UserService', 1, true) ~= nil)

ui.open_stack_popup()
vim.wait(50)
support.expect_equal('dap ui stack popup kind', ui._state.popup.kind, 'stack_list')
local stack_text = table.concat(vim.api.nvim_buf_get_lines(ui._state.popup.bufnr, 0, -1, false), '\n')
support.expect_true('dap ui stack popup shows external frame before filter', stack_text:find('external.Library.call', 1, true) ~= nil)
ui.toggle_stack_filter()
vim.wait(50)
stack_text = table.concat(vim.api.nvim_buf_get_lines(ui._state.popup.bufnr, 0, -1, false), '\n')
support.expect_true('dap ui stack popup filters to project frames', stack_text:find('external.Library.call', 1, true) == nil and stack_text:find('Service.run', 1, true) ~= nil)

stacktrace_calls = 0
ui.run_action('step_project')
package.loaded['dap'].listeners.before.event_continued.user_dap_panels()
vim.wait(50)
ui.handle_stopped(nil, { threadId = 3 })
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
local step_out_count = 0
for _, name in ipairs(request_names) do
  if name == 'stepIn' then
    step_in_count = step_in_count + 1
  elseif name == 'stepOut' then
    step_out_count = step_out_count + 1
  end
end
support.expect_equal('dap ui project step keeps initial stepIn only once', step_in_count, 1)
support.expect_true('dap ui project step unwinds external frames with stepOut', step_out_count >= 2)

ui.run_action('step_raw')
support.expect_equal('dap ui raw step into bypasses project logic', package.loaded['dap']._step_into, 1)
ui.handle_stopped(nil, { threadId = 3 })
vim.wait(50)
ui.run_action('next')
support.expect_true('dap ui enter-repeat consumes running session input', ui.repeat_last_action())
support.expect_equal('dap ui enter-repeat does not step while running', package.loaded['dap']._step_over, 1)
ui.handle_stopped(nil, { threadId = 3 })
vim.wait(50)
ui.repeat_last_action()
support.expect_equal('dap ui enter-repeat replays last action after stop', package.loaded['dap']._step_over, 2)
local original_session = dap_stub.session
dap_stub.session = function()
  return nil
end
support.expect_true('dap ui continue guard blocks without session', not ui.run_action('continue'))
support.expect_equal('dap ui continue guard notifies without session', notifications[#notifications], 'No active DAP session.')
dap_stub.session = original_session

vim.cmd('edit ' .. vim.fn.fnameescape(tmpfile))
vim.api.nvim_win_set_cursor(0, { 10, 0 })
ui.toggle_breakpoint_here()
support.expect_equal('dap ui breakpoint toggles current line', package.loaded['dap']._breakpoint_line, 10)
support.expect_equal(
  'dap ui breakpoint uses current file',
  vim.uv.fs_realpath(package.loaded['dap']._breakpoint_file),
  vim.uv.fs_realpath(tmpfile)
)

ui._state.session_stopped = true
ui._state.last_action = 'next'
package.loaded['dap'].listeners.before.event_terminated.user_dap_panels(nil, {})
support.expect_equal('dap ui terminated clears last_action', ui._state.last_action, nil)
support.expect_equal('dap ui terminated clears session_stopped', ui._state.session_stopped, false)

vim.notify = original_notify
package.loaded['dap'] = original_dap
pcall(vim.fn.delete, tmpfile)

support.flush()
