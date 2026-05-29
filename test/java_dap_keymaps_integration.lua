local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

package.loaded['user.dap'] = nil
package.loaded['user.dap_ui'] = nil

local original_dap = package.loaded['dap']
local original_java = package.loaded['java']
local original_notify = vim.notify
local original_get_clients = vim.lsp.get_clients
local original_win_close = vim.api.nvim_win_close

local notifications = {}
local step_requests = {}
local stack_frames = {}
local project_root = vim.fs.normalize(vim.fn.stdpath('config') .. '/test-projects/java17-spring-demo')
local controller_file = project_root .. '/src/main/java/com/example/demo/controller/UserController.java'
local service_impl_file = project_root .. '/src/main/java/com/example/demo/service/impl/UserServiceImpl.java'
local service_impl_lines = vim.fn.readfile(service_impl_file)
local service_return_line = 1
for index, line in ipairs(service_impl_lines) do
  if line:find('return ', 1, true) then
    service_return_line = index
    break
  end
end

local tracked_popup_win = nil
local popup_close_calls = 0

local dap_stub = {}

dap_stub.listeners = {
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
}

dap_stub.run = function(config)
  dap_stub._run_config = vim.deepcopy(config)
end

local function push_stack_frame(path, line)
  table.insert(stack_frames, {
    id = #stack_frames + 1,
    name = 'frame-' .. tostring(#stack_frames + 1),
    line = line,
    source = path and { path = path } or nil,
  })
end

dap_stub._session = {
  request = function(_, command, args, callback)
    table.insert(step_requests, {
      command = command,
      args = args and vim.deepcopy(args) or nil,
    })
    if command == 'stackTrace' then
      local frame = table.remove(stack_frames, 1)
      callback(nil, { stackFrames = frame and { frame } or {} })
      return
    end
    callback(nil, {})
  end,
}

dap_stub.session = function()
  return dap_stub._session
end

dap_stub.continue = function()
  dap_stub._continue = (dap_stub._continue or 0) + 1
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

package.loaded['dap'] = dap_stub
package.loaded['java'] = {
  dap = {
    config_dap = function() end,
  },
}

vim.notify = function(message)
  table.insert(notifications, tostring(message))
end

vim.lsp.get_clients = function(opts)
  if opts and opts.name == 'jdtls' then
    return {
      {
        name = 'jdtls',
        config = {
          root_dir = project_root,
        },
      },
    }
  end
  return {}
end

vim.api.nvim_win_close = function(win, force)
  if tracked_popup_win and win == tracked_popup_win then
    popup_close_calls = popup_close_calls + 1
  end
  return original_win_close(win, force)
end

vim.cmd('set noswapfile')
vim.cmd('edit ' .. vim.fn.fnameescape(controller_file))
vim.cmd('lcd ' .. vim.fn.fnameescape(project_root))

local ui = require('user.dap_ui')
ui.ensure_listeners()

vim.cmd('DebugStart')
tracked_popup_win = vim.api.nvim_get_current_win()
support.feed('2<CR>')
vim.wait(120)

support.expect_equal('java dap start command chooses launch config', dap_stub._run_config and dap_stub._run_config.name, 'launch')
support.expect_equal('java dap start command explicitly closes popup window', popup_close_calls, 1)
support.expect_true('java dap start command removes popup window', not vim.api.nvim_win_is_valid(tracked_popup_win))

ui.set_project_root(project_root)
ui._state.session_stopped = true
ui._state.current_thread_id = 16
ui.run_action('step_project')
push_stack_frame('jdt:/contents/spring-aop-6.1.11.jar/org.springframework.aop.framework/CglibAopProxy.class', 693)
ui.handle_stopped(nil, { threadId = 16 })
vim.wait(80)
support.expect_equal('java dap step_project starts with stepIn request', step_requests[1].command, 'stepIn')
support.expect_equal('java dap step_project escapes jdt frames with stepOut', step_requests[#step_requests].command, 'stepOut')

dap_stub.listeners.before.event_terminated.user_dap_panels(nil, { type = 'terminated' })
support.expect_true(
  'java dap step_project termination reports visible warning',
  notifications[#notifications]:find('terminated', 1, true) ~= nil
    and notifications[#notifications]:find('CglibAopProxy.class', 1, true) ~= nil
)

step_requests = {}
stack_frames = {}
dap_stub._step_over = 0
dap_stub._step_out = 0
ui._state.session_stopped = true
push_stack_frame(service_impl_file, service_return_line)
ui.handle_stopped(nil, { threadId = 16 })
vim.wait(80)
ui.run_action('next')
ui.repeat_last_action()
support.expect_equal('java dap repeat_last_action ignores running next at method boundary', dap_stub._step_over, 1)
push_stack_frame('jdt:/contents/spring-aop-6.1.11.jar/org.springframework.aop.framework/CglibAopProxy.class', 694)
ui.handle_stopped(nil, { threadId = 16 })
vim.wait(80)
ui.repeat_last_action()
support.expect_equal('java dap repeat_last_action keeps next in jdt frame instead of stepOut', dap_stub._step_over, 2)

vim.api.nvim_win_close = original_win_close
vim.lsp.get_clients = original_get_clients
vim.notify = original_notify
package.loaded['dap'] = original_dap
package.loaded['java'] = original_java

support.flush()
