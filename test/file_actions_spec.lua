local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
local file_actions = require('user.file_actions')

local temp_root = vim.fn.tempname()
vim.fn.mkdir(temp_root, 'p')
temp_root = vim.uv.fs_realpath(temp_root) or vim.fs.normalize(temp_root)

local original_path = vim.fs.normalize(temp_root .. '/sample.txt')
local renamed_path = vim.fs.normalize(temp_root .. '/renamed.txt')
vim.fn.writefile({ 'alpha', 'beta' }, original_path)

vim.cmd('edit ' .. vim.fn.fnameescape(original_path))
support.expect_equal('file action initial buffer name', vim.api.nvim_buf_get_name(0), original_path)

support.expect_true('file action rename succeeds', file_actions.rename_path(original_path, { new_name = 'renamed.txt' }))
support.expect_true('file action renamed file exists', vim.uv.fs_stat(renamed_path) ~= nil)
support.expect_true('file action old file removed', vim.uv.fs_stat(original_path) == nil)
support.expect_equal('file action buffer renamed', vim.api.nvim_buf_get_name(0), renamed_path)

local renamed_buf = vim.api.nvim_get_current_buf()
support.expect_true('file action delete succeeds', file_actions.delete_path(renamed_path, { skip_confirm = true }))
support.expect_true('file action deleted file removed from disk', vim.uv.fs_stat(renamed_path) == nil)
support.expect_true('file action buffer retained after delete', vim.api.nvim_buf_is_valid(renamed_buf))
support.expect_equal('file action buffer name retained after delete', vim.api.nvim_buf_get_name(renamed_buf), renamed_path)

local dirvish_root = vim.fs.normalize(temp_root .. '/dirvish')
vim.fn.mkdir(dirvish_root, 'p')
vim.fn.writefile({ 'entry' }, dirvish_root .. '/entry.txt')
vim.cmd('Dirvish ' .. vim.fn.fnameescape(dirvish_root))
vim.wait(100)

support.expect_equal('dirvish filetype', vim.bo.filetype, 'dirvish')
support.expect_equal('dirvish leader bx mapping desc', vim.fn.maparg('<leader>bx', 'n', false, true).desc, 'Buffer: Run shell command on selected file')
support.expect_equal('dirvish leader br mapping desc', vim.fn.maparg('<leader>br', 'n', false, true).desc, 'Buffer: Rename selected file')
support.expect_equal('dirvish leader bd mapping desc', vim.fn.maparg('<leader>bd', 'n', false, true).desc, 'Buffer: Delete selected file from disk')
support.expect_equal('dirvish delete mapping desc', vim.fn.maparg('D', 'n', false, true).desc, 'Delete file from disk')

vim.cmd('bdelete!')
vim.fn.delete(temp_root, 'rf')

support.flush()
