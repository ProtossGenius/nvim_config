local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

support.reset({
  'public class Demo {',
  '    public void test() {',
  '        int a = 1;',
  '        int b = 2;',
  '        int sum = a + b;',
  '    }',
  '}'
}, 'java', 'java')

-- Wait for jdtls
local bufnr = vim.api.nvim_get_current_buf()
local attached = false
for i = 1, 30 do
  vim.wait(500, function() return false end)
  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = 'jdtls' })
  if #clients > 0 and clients[1].initialized then
    attached = true
    break
  end
end
support.expect_true("JDTLS attached", attached)

-- Set visual mode over `a + b`
vim.fn.setpos("'<", { bufnr, 5, 19, 0 })
vim.fn.setpos("'>", { bufnr, 5, 23, 0 })
vim.api.nvim_win_set_cursor(0, {5, 18})
vim.cmd('normal! V')

local success = false
vim.lsp.buf.rename = function(new_name, options)
  local params = vim.lsp.util.make_position_params()
  params.newName = "newVariable"
  vim.lsp.buf_request(0, "textDocument/rename", params, function(err, result, ctx, config)
    if result then
      vim.lsp.util.apply_workspace_edit(result, "utf-16")
    end
  end)
end

vim.ui.input = function(opts, on_confirm)
  on_confirm("newVariable")
end

for i = 1, 10 do
  -- Esc out of visual mode and run extract variable (to simulate the keymap fix we did)
  vim.cmd('normal! \27')
  require('jdtls').extract_variable(true)
  
  -- Wait 1 second
  vim.wait(1000, function() return false end)
  
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")
  -- Just check if a new variable was introduced, or the buffer changed
  if content:find("newVariable") or content:find("sum = a %+ b;") == nil then
    success = true
    break
  end
end

support.expect_true("Extract variable modified buffer", success)

support.flush()
