local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

local controller_file = vim.fn.stdpath('config') .. '/test-projects/java17-spring-demo/core/src/main/java/com/example/demo/controller/UserController.java'

_G.initial_cwd = vim.fn.stdpath('config') .. '/test-projects/java17-spring-demo'
vim.cmd('cd ' .. vim.fn.fnameescape(_G.initial_cwd))
vim.cmd('edit ' .. vim.fn.fnameescape(controller_file))
vim.bo.swapfile = false

local attached = vim.wait(60000, function()
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    if client.name == 'jdtls' then
      return true
    end
  end
  return false
end, 200)

support.expect_true('java completion client attached', attached)

local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local create_user_line = nil
for idx, line in ipairs(lines) do
  if line:find('return userService.createUser', 1, true) then
    create_user_line = idx
    break
  end
end

support.expect_true('java completion found createUser line', create_user_line ~= nil)
vim.api.nvim_buf_set_lines(0, create_user_line - 1, create_user_line, false, { '    request.' })
local request_line = vim.api.nvim_buf_get_lines(0, create_user_line - 1, create_user_line, false)[1]
local request_col = request_line:find('request%.', 1) or 1
vim.api.nvim_win_set_cursor(0, { create_user_line, request_col - 1 + #'request.' })
vim.wait(300)

local done = false
local completion_err = nil
local completion_result = nil
vim.lsp.buf_request(0, 'textDocument/completion', vim.lsp.util.make_position_params(), function(err, result)
  completion_err = err
  completion_result = result
  done = true
end)
vim.wait(10000, function() return done end)

support.expect_true('java completion request. response received', done)
if completion_err then
  print('request completion error: ' .. vim.inspect(completion_err))
end
support.expect_true('java completion request. succeeds', completion_err == nil)
local items = completion_result and completion_result.items or {}
local by_label = {}
for _, item in ipairs(items) do
  by_label[item.label] = item
end
for _, name in ipairs({ 'getName', 'getEmail', 'setName', 'setEmail' }) do
  support.expect_true('java completion request. contains ' .. name, by_label[name] ~= nil)
end
support.expect_equal('java completion setter snippet inserts first parameter placeholder', by_label.setEmail.insertText, 'setEmail(${1:email})')

vim.api.nvim_buf_set_lines(0, create_user_line - 1, create_user_line, false, { '    List<User> users = userService.' })
local service_line = vim.api.nvim_buf_get_lines(0, create_user_line - 1, create_user_line, false)[1]
local service_col = service_line:find('userService%.', 1) or 1
vim.api.nvim_win_set_cursor(0, { create_user_line, service_col - 1 + #'userService.' })
vim.wait(300)

done = false
completion_err = nil
completion_result = nil
vim.lsp.buf_request(0, 'textDocument/completion', vim.lsp.util.make_position_params(), function(err, result)
  completion_err = err
  completion_result = result
  done = true
end)
vim.wait(10000, function() return done end)

support.expect_true('java completion userService. response received', done)
if completion_err then
  print('userService completion error: ' .. vim.inspect(completion_err))
end
support.expect_true('java completion userService. succeeds', completion_err == nil)
items = completion_result and completion_result.items or {}
support.expect_true('java completion userService. has results', #items > 0)
support.expect_equal('java completion ranks listUsers first for List<User> assignment', items[1].label, 'listUsers')

vim.cmd('bdelete!')
support.flush()
