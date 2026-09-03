local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
local indexing = require('user.indexing')
local telescope_search = require('user.telescope_search')

local original_no_auto_index_dirs = vim.g.no_auto_index_dirs
local original_no_auto_index_recursive_dirs = vim.g.no_auto_index_recursive_dirs
local original_no_auto_index_ignore_globs = vim.g.no_auto_index_ignore_globs
local original_no_auto_index_follow_symlinks = vim.g.no_auto_index_follow_symlinks

local temp_root = vim.fn.tempname()
vim.fn.mkdir(temp_root .. '/child', 'p')
local recursive_root = temp_root .. '/recursive'
vim.fn.mkdir(recursive_root .. '/child', 'p')

vim.g.no_auto_index_dirs = { temp_root }
vim.g.no_auto_index_recursive_dirs = { recursive_root }
vim.g.no_auto_index_ignore_globs = nil
vim.g.no_auto_index_follow_symlinks = false

support.expect_true('exact no-auto-index dir matches itself', indexing.is_no_auto_index_dir(temp_root))
support.expect_true('exact no-auto-index dir does not match child', not indexing.is_no_auto_index_dir(temp_root .. '/child'))
support.expect_true('recursive no-auto-index dir matches child', indexing.is_no_auto_index_dir(recursive_root .. '/child'))

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_name(buf, temp_root)
support.expect_true('directory guard handles configured dir', indexing.guard_directory_buffer(buf))
support.expect_equal('directory guard uses placeholder filetype', vim.bo[buf].filetype, 'noautoindex')
support.expect_equal('search cwd uses guarded directory buffer', indexing.search_cwd(), vim.fs.normalize(temp_root))

support.expect_equal('realtime fuzzy glob uses prompt chars', telescope_search._test.prompt_to_fuzzy_glob('abc'), '*a*b*c*')
support.expect_equal('realtime fuzzy glob skips spaces', telescope_search._test.prompt_to_fuzzy_glob('a b'), '*a*b*')

local realtime_find_command = telescope_search._test.base_find_command(temp_root, true)
local project_find_command = telescope_search._test.base_find_command(temp_root, false)
support.expect_true('realtime file command skips symlink following by default', not vim.tbl_contains(realtime_find_command, '--follow'))
support.expect_true('project file command keeps symlink following', vim.tbl_contains(project_find_command, '--follow'))
support.expect_true('realtime file command ignores cache dirs', vim.tbl_contains(realtime_find_command, '!.cache/**'))

vim.api.nvim_buf_delete(buf, { force = true })
vim.fn.delete(temp_root, 'rf')

vim.g.no_auto_index_dirs = original_no_auto_index_dirs
vim.g.no_auto_index_recursive_dirs = original_no_auto_index_recursive_dirs
vim.g.no_auto_index_ignore_globs = original_no_auto_index_ignore_globs
vim.g.no_auto_index_follow_symlinks = original_no_auto_index_follow_symlinks

support.flush()
