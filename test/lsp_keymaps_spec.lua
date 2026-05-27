local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
local user_lsp = require('user.lsp')

local original_format = vim.lsp.buf.format
local format_calls = {}

vim.lsp.buf.format = function(opts)
  table.insert(format_calls, opts)
end

support.reset({
  'first line',
  'second line',
  'third line',
}, 'lua', 'lua')

local fake_client = {
  name = 'fake-lsp',
  server_capabilities = {
    documentFormattingProvider = true,
  },
  supports_method = function(_, method)
    return method == 'textDocument/rangeFormatting'
  end,
}

user_lsp.on_attach(fake_client, 0)

support.expect_equal('lsp normal format mapping desc', vim.fn.maparg('<leader>lf', 'n', false, true).desc, 'LSP: Format buffer')
support.expect_equal('lsp visual format mapping desc', vim.fn.maparg('<leader>lf', 'x', false, true).desc, 'LSP: Format selection')

vim.fn.setpos("'<", { 0, 1, 1, 0 })
vim.fn.setpos("'>", { 0, 2, 7, 0 })
vim.fn.maparg('<leader>lf', 'x', false, true).callback()

support.expect_equal('lsp visual format passes range', format_calls[1], {
  async = true,
  range = {
    start = { 0, 0 },
    ['end'] = { 1, 7 },
  },
})

vim.lsp.buf.format = original_format

support.flush()
