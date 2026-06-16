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

support.expect_true('java hover/typeDefinition client attached', attached)

local function request(method, needle, offset)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for idx, line in ipairs(lines) do
    local col = line:find(needle, 1, true)
    if col then
      vim.api.nvim_win_set_cursor(0, { idx, col - 1 + (offset or 0) })
      local done = false
      local err_out = nil
      local result_out = nil
      vim.lsp.buf_request(0, method, vim.lsp.util.make_position_params(), function(err, result)
        err_out = err
        result_out = result
        done = true
      end)
      vim.wait(10000, function() return done end)
      return err_out, result_out
    end
  end
  return { message = 'needle not found: ' .. needle }, nil
end

local err, result = request('textDocument/typeDefinition', 'userService.listUsers', #'userService.listUsers')
support.expect_true('java typeDefinition succeeds', err == nil)
local type_uri = result and result[1] and result[1].uri or ''
support.expect_true('java typeDefinition opens List source', type_uri:find('List%.java', 1) ~= nil)

err, result = request('textDocument/hover', 'userService.listUsers', #'userService.listUsers')
support.expect_true('java hover succeeds', err == nil)
local hover_value = result and result.contents and result.contents.value or ''
support.expect_true('java hover shows listUsers signature', hover_value:find('List<User> listUsers(', 1, true) ~= nil)
support.expect_true('java hover shows listUsers documentation', hover_value:find('Lists all persisted users.', 1, true) ~= nil)

vim.cmd('bdelete!')
support.flush()
