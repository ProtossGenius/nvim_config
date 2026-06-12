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

support.expect_true('java diagnostics client attached', attached)

local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local create_user_line = nil
for idx, line in ipairs(lines) do
  if line:find('return userService.createUser', 1, true) then
    create_user_line = idx
    break
  end
end

support.expect_true('java diagnostics found createUser line', create_user_line ~= nil)
vim.api.nvim_buf_set_lines(0, create_user_line - 1, create_user_line - 1, false, {
  '    List<User1> users = userService.listUsers();',
})
vim.wait(300)

local diagnostics = {}
local diagnostics_ready = vim.wait(10000, function()
  diagnostics = vim.diagnostic.get(0)
  for _, diagnostic in ipairs(diagnostics) do
    if diagnostic.message and diagnostic.message:find('User1', 1, true) then
      return true
    end
  end
  return false
end, 200)
support.expect_true('java diagnostics published', diagnostics_ready)
support.expect_true('java diagnostics contain unresolved User1', diagnostics_ready)

vim.cmd('bdelete!')
support.flush()
