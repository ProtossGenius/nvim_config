local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

local service_file = vim.fn.stdpath('config') .. '/test-projects/java17-spring-demo/core/src/main/java/com/example/demo/service/impl/UserServiceImpl.java'

_G.initial_cwd = vim.fn.stdpath('config') .. '/test-projects/java17-spring-demo'
vim.cmd('cd ' .. vim.fn.fnameescape(_G.initial_cwd))
vim.cmd('edit ' .. vim.fn.fnameescape(service_file))
vim.bo.swapfile = false

local attached = vim.wait(60000, function()
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    if client.name == 'jdtls' then
      return true
    end
  end
  return false
end, 200)

support.expect_true('java navigation client attached', attached)

local client = vim.lsp.get_clients({ bufnr = 0 })[1]
support.expect_true('java navigation declaration is supported', client and client:supports_method('textDocument/declaration') or false)
support.expect_true('java navigation implementation is supported', client and client:supports_method('textDocument/implementation') or false)

local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local info_line = nil
for idx, line in ipairs(lines) do
  if line:find('log.info', 1, true) then
    info_line = idx
    break
  end
end

support.expect_true('java navigation found log.info line', info_line ~= nil)
local log_col = lines[info_line]:find('log', 1, true) or 1
local info_col = lines[info_line]:find('info', 1, true) or 1
vim.api.nvim_win_set_cursor(0, { info_line, log_col - 1 })
vim.wait(200)

local done = false
local declaration_result = nil
local declaration_err = nil
vim.lsp.buf_request(0, 'textDocument/declaration', vim.lsp.util.make_position_params(), function(err, result)
  declaration_err = err
  declaration_result = result
  done = true
end)
vim.wait(10000, function() return done end)

support.expect_true('java navigation declaration response received', done)
if declaration_err then
  print('declaration error: ' .. vim.inspect(declaration_err))
end
support.expect_true('java navigation declaration succeeds', declaration_err == nil)
support.expect_true('java navigation declaration has locations', type(declaration_result) == 'table' and #declaration_result >= 1)
local declaration_uri = declaration_result and declaration_result[1] and declaration_result[1].uri or ''
support.expect_true('java navigation declaration opens slf4j Logger source', declaration_uri:find('Logger%.java', 1) ~= nil)

done = false
local implementation_result = nil
local implementation_err = nil
vim.lsp.buf_request(0, 'textDocument/implementation', vim.lsp.util.make_position_params(), function(err, result)
  implementation_err = err
  implementation_result = result
  done = true
end)
vim.wait(10000, function() return done end)

support.expect_true('java navigation implementation response received', done)
if implementation_err then
  print('implementation error: ' .. vim.inspect(implementation_err))
end
support.expect_true('java navigation implementation succeeds', implementation_err == nil)
support.expect_true('java navigation implementation has locations', type(implementation_result) == 'table' and #implementation_result >= 1)
local implementation_uri = implementation_result and implementation_result[1] and implementation_result[1].uri or ''
support.expect_true('java navigation implementation opens logback Logger source', implementation_uri:find('logback%-classic', 1) ~= nil)

local done_completion = false
local completion_err = nil
local completion_result = nil
vim.api.nvim_win_set_cursor(0, { info_line, log_col + 3 })
vim.lsp.buf_request(0, 'textDocument/completion', vim.lsp.util.make_position_params(), function(err, result)
  completion_err = err
  completion_result = result
  done_completion = true
end)
vim.wait(10000, function() return done_completion end)

support.expect_true('java navigation completion response received', done_completion)
support.expect_true('java navigation completion succeeds', completion_err == nil)
local completion_items = completion_result and completion_result.items or {}
local has_info = false
for _, item in ipairs(completion_items) do
  if item.label == 'info' then
    has_info = true
    break
  end
end
support.expect_true('java navigation completion contains info', has_info)

vim.cmd('bdelete!')
support.flush()
