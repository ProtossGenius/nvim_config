local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

-- 1. Test Treesitter get_node_text and get_range table compatibility (Neovim 0.12)
local ok_ts, ts = pcall(require, 'vim.treesitter')
support.expect_true('treesitter module loaded', ok_ts)

-- Test with empty table
local empty_text = vim.treesitter.get_node_text({}, 0)
support.expect_equal('get_node_text on empty table returns empty string', empty_text, '')

local empty_range = vim.treesitter.get_range({}, 0)
support.expect_equal('get_range on empty table returns zero range', empty_range, { 0, 0, 0, 0 })

-- 2. Test markdown floating preview with code blocks (simulating completion docs, hover, signature help)
local doc_lines = {
  '# Function string.format',
  '```lua',
  'function string.format(s, ...)',
  '```',
  'Formats values according to format specifier.',
}

local ok_preview, f_bufnr, f_winnr = pcall(function()
  local b, w = vim.lsp.util.open_floating_preview(doc_lines, 'markdown', {
    border = 'rounded',
  })
  if w and vim.api.nvim_win_is_valid(w) then
    vim.api.nvim_win_set_cursor(w, { 1, 0 })
  end
  vim.cmd('redraw')
  return b, w
end)

support.expect_true('markdown floating preview opens without error', ok_preview)
if f_winnr and vim.api.nvim_win_is_valid(f_winnr) then
  pcall(vim.api.nvim_win_close, f_winnr, true)
end
if f_bufnr and vim.api.nvim_buf_is_valid(f_bufnr) then
  pcall(vim.api.nvim_buf_delete, f_bufnr, { force = true })
end

-- 3. Test signature help handler does not print on nil / empty signatures
local function get_last_message()
  local msgs = vim.fn.split(vim.fn.execute('messages'), '\n')
  return msgs[#msgs] or ''
end

vim.cmd('messages clear')
local cur_buf = vim.api.nvim_get_current_buf()

local sig_handler = vim.lsp.handlers["textDocument/signatureHelp"]
support.expect_true('signatureHelp handler is configured', type(sig_handler) == 'function')

sig_handler(nil, nil, { method = 'textDocument/signatureHelp', client_id = 1, bufnr = cur_buf }, { silent = true })
support.expect_true('signatureHelp silent on nil result', not get_last_message():find('No signature help available'))

sig_handler(nil, { signatures = {} }, { method = 'textDocument/signatureHelp', client_id = 1, bufnr = cur_buf }, { silent = true })
support.expect_true('signatureHelp silent on empty signatures', not get_last_message():find('No signature help available'))

-- 4. Test normal function typing and completion in a buffer without luabind
local plain_bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(plain_bufnr)
vim.bo[plain_bufnr].filetype = 'lua'

local luabind = require('user.luabind')
luabind.attach_to_buffer(plain_bufnr)

vim.api.nvim_buf_set_lines(plain_bufnr, 0, -1, false, { 'local x = math.abs(-5)' })
vim.api.nvim_win_set_cursor(0, { 1, 18 })

local ok_hint, err_hint = pcall(function()
  luabind.update_insert_hint(plain_bufnr)
end)
support.expect_true('update_insert_hint in non-luabind buffer succeeds silently', ok_hint and err_hint == nil)

-- 5. Test normal function typing in a buffer with luabind (demo project)
local demo_path = vim.fn.fnamemodify('test-projects/lua-luabind-demo/scripts/game.lua', ':p')
local demo_bufnr = vim.fn.bufadd(demo_path)
vim.fn.bufload(demo_bufnr)
vim.api.nvim_set_current_buf(demo_bufnr)
luabind.attach_to_buffer(demo_bufnr)

-- Type normal function math.max(
vim.api.nvim_buf_set_lines(demo_bufnr, -1, -1, false, { 'local m = math.max(1, 2)' })
local line_count = vim.api.nvim_buf_line_count(demo_bufnr)
vim.api.nvim_win_set_cursor(0, { line_count, 20 })

local ok_norm, err_norm = pcall(function()
  luabind.update_insert_hint(demo_bufnr)
end)
support.expect_true('update_insert_hint for normal function in luabind project succeeds', ok_norm and err_norm == nil)

-- Type luabind method Player:take_damage(
vim.api.nvim_buf_set_lines(demo_bufnr, -1, -1, false, { 'Player:take_damage(50)' })
line_count = vim.api.nvim_buf_line_count(demo_bufnr)
vim.api.nvim_win_set_cursor(0, { line_count, 19 })

local ok_lb, err_lb = pcall(function()
  luabind.update_insert_hint(demo_bufnr)
end)
support.expect_true('update_insert_hint for luabind method succeeds', ok_lb and err_lb == nil)

-- Clean up call hint
luabind.close_call_hint()

-- 6. Verify cmp sources don't crash when completing normal functions
local cmp = require('cmp')
support.expect_true('cmp is loaded', cmp ~= nil)

local items = luabind.get_cmp_items({
  context = {
    bufnr = demo_bufnr,
    cursor_before_line = 'math.m',
  },
})
support.expect_equal('luabind cmp items empty for math. prefix', #items, 0)

-- Clean up buffers
pcall(vim.api.nvim_buf_delete, plain_bufnr, { force = true })
pcall(vim.api.nvim_buf_delete, demo_bufnr, { force = true })

support.flush()
print("All normal function completion regression tests passed successfully!")
