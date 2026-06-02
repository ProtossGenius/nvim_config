local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
package.loaded['telescope.builtin'] = {
  lsp_document_symbols = function() end,
  lsp_dynamic_workspace_symbols = function() end,
}
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
support.expect_equal('lsp class jump mapping desc', vim.fn.maparg('<leader>lc', 'n', false, true).desc, 'LSP: Jump to class')

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

-- Test textDocument/signatureHelp error suppression
local original_handler = vim.lsp.handlers["textDocument/signatureHelp"]
local called_with = nil
vim.lsp.handlers["textDocument/signatureHelp"] = function(err, result, ctx, config)
  called_with = { err = err, result = result }
end

package.loaded['user.lsp'] = nil
user_lsp = require('user.lsp')

local wrapper_handler = vim.lsp.handlers["textDocument/signatureHelp"]

-- Call with error, should return silently and NOT forward the call
called_with = nil
local ok, ret = pcall(wrapper_handler, { code = -32603, message = "Internal error" }, nil, nil, nil)
support.expect_true('signatureHelp error handler call succeeds', ok)
support.expect_equal('signatureHelp error is suppressed and not forwarded', called_with, nil)

-- Call without error, should forward the call
called_with = nil
wrapper_handler(nil, { signatures = {} }, nil, nil)
support.expect_true('signatureHelp normal call is forwarded', called_with ~= nil)
support.expect_equal('signatureHelp normal call payload', called_with.result, { signatures = {} })

-- Restore
vim.lsp.handlers["textDocument/signatureHelp"] = original_handler

support.flush()
