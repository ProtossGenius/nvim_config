local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

local controller_file = vim.fn.stdpath('config') .. '/test-projects/java17-spring-demo/core/src/main/java/com/example/demo/controller/UserController.java'

-- Set initial_cwd to the java demo project root so JDTLS starts correctly
_G.initial_cwd = vim.fn.stdpath('config') .. '/test-projects/java17-spring-demo'
vim.cmd('cd ' .. vim.fn.fnameescape(_G.initial_cwd))

print("Opening controller file...")
vim.cmd('edit ' .. vim.fn.fnameescape(controller_file))

-- Wait for JDTLS to attach
local attached = vim.wait(60000, function()
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    if client.name == 'jdtls' then
      return true
    end
  end
  return false
end, 200)

support.expect_true('JDTLS attached to UserController', attached)

-- Find the line with String.format
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local format_line_idx = nil
for idx, line in ipairs(lines) do
  if line:find("String.format", 1, true) then
    format_line_idx = idx
    break
  end
end

support.expect_true('Found String.format line', format_line_idx ~= nil)
print("String.format line index: " .. tostring(format_line_idx))

-- Position the cursor inside String.format("hello world %d", id)
-- Specifically, put the cursor inside the parenthesis e.g. after the opening quote
-- "       String.format("hello world %d", id);"
-- Character offset for "hello" is around 22
vim.api.nvim_win_set_cursor(0, { format_line_idx, 23 })
vim.wait(200)

-- Trigger textDocument/signatureHelp via direct LSP client request to verify JDTLS response
print("Sending textDocument/signatureHelp request to JDTLS...")
local done = false
local response_err = nil
local response_result = nil

local params = vim.lsp.util.make_position_params()
vim.lsp.buf_request(0, 'textDocument/signatureHelp', params, function(err, result, ctx)
  response_err = err
  response_result = result
  done = true
end)

vim.wait(10000, function() return done end)

support.expect_true('LSP response received', done)
support.expect_true('JDTLS returns an RPC error', response_err ~= nil)
if response_err then
  print("Captured RPC Error Code: " .. tostring(response_err.code))
  print("Captured RPC Error Message: " .. tostring(response_err.message))
  support.expect_equal('RPC error is InternalError', response_err.code, -32603)
  support.expect_true('RPC error message contains ClassCastException', response_err.data:find("ClassCastException", 1, true) ~= nil)
end

-- Verify that the global signatureHelp handler wrapper handles it gracefully
-- Check if lsp_signature is loaded and its config can be customized to suppress this error
local ok_lsp_sig, lsp_sig = pcall(require, 'lsp_signature')
if ok_lsp_sig then
  print("lsp_signature plugin is loaded. Testing suppression config.")
  
  -- Test the default / current setup config for ignore_error
  local ignore_error_fn = _LSP_SIG_CFG and _LSP_SIG_CFG.ignore_error
  support.expect_true('lsp_signature ignore_error function is defined', type(ignore_error_fn) == 'function')
  
  if type(ignore_error_fn) == 'function' then
    local ctx = { client_id = vim.lsp.get_clients({ bufnr = 0 })[1].id }
    local should_ignore = ignore_error_fn(response_err, ctx, {})
    print("Should ignore error according to ignore_error callback: " .. tostring(should_ignore))
    support.expect_true('ignore_error callback returns true for JDTLS ClassCastException', should_ignore == true)
  end
end

vim.cmd('bdelete!')
support.flush()
