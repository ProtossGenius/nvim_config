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

support.expect_true('java jdk navigation client attached', attached)

local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local runtime_line = nil
for idx, line in ipairs(lines) do
  if line:find('RuntimeException', 1, true) then
    runtime_line = idx
    break
  end
end

support.expect_true('java jdk navigation found RuntimeException line', runtime_line ~= nil)
local runtime_col = lines[runtime_line]:find('RuntimeException', 1, true) or 1
vim.api.nvim_win_set_cursor(0, { runtime_line, runtime_col - 1 + 2 })

local done = false
local response_err = nil
local response_result = nil
vim.lsp.buf_request(0, 'textDocument/definition', vim.lsp.util.make_position_params(), function(err, result)
  response_err = err
  response_result = result
  done = true
end)
vim.wait(10000, function() return done end)

support.expect_true('java jdk navigation response received', done)
support.expect_true('java jdk navigation succeeds', response_err == nil)
local uri = response_result and response_result[1] and response_result[1].uri or ''
support.expect_true('java jdk navigation opens RuntimeException source', uri:find('RuntimeException%.java', 1) ~= nil)

vim.cmd('bdelete!')
support.flush()

