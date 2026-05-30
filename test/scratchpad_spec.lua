local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
local scratchpad = require('user.scratchpad')

-- 1. Mock a buffer and test scratchpad opening and temporary file generation
local temp_dir = vim.fn.tempname()
vim.fn.mkdir(temp_dir, 'p')
temp_dir = vim.uv.fs_realpath(temp_dir) or vim.fs.normalize(temp_dir)

local mock_java_file = temp_dir .. '/Main.java'
vim.fn.writefile({
  'package com.example.test;',
  'public class Main {}'
}, mock_java_file)

-- Open the mock file in buffer
vim.cmd('edit ' .. vim.fn.fnameescape(mock_java_file))

-- Open scratchpad
scratchpad.open_scratchpad()

-- Check that a new buffer was created and is active
local current_buf = vim.api.nvim_get_current_buf()
local current_name = vim.api.nvim_buf_get_name(current_buf)
support.expect_true('Scratchpad buffer is active', current_name:find('Scratchpad%.java$') ~= nil)

-- Verify that the temporary class file was written to disk with correct package
local scratch_content = table.concat(vim.api.nvim_buf_get_lines(current_buf, 0, -1, false), '\n')
support.expect_true('Scratchpad package is correct', scratch_content:find('package com%.example%.test;') ~= nil)
support.expect_true('Scratchpad class is Scratchpad', scratch_content:find('public class Scratchpad') ~= nil)

-- 2. Test inline execution and result appending
-- Pre-populate the buffer with a simple print statement in Java Scratchpad
vim.api.nvim_buf_set_lines(current_buf, 9, 10, false, { '        System.out.println("Hello from Scratchpad!");' })

-- Simulate pressing <CR> or running code
vim.cmd('write')
-- Trigger running
local run_scratchpad = require('user.scratchpad')._test_run
run_scratchpad(current_buf, current_name, 'java')

-- Verify that the buffer now contains the comment result block
local updated_content = table.concat(vim.api.nvim_buf_get_lines(current_buf, 0, -1, false), '\n')
support.expect_true('Scratchpad contains result block', updated_content:find('/%*+ result %*+') ~= nil)
support.expect_true('Scratchpad contains actual output', updated_content:find('Hello from Scratchpad!') ~= nil)
support.expect_true('Scratchpad contains output end', updated_content:find('%*+ output end %*+/') ~= nil)

-- Wipe out the buffer to trigger BufWipeout autocmd cleanup
vim.cmd('bwipeout!')

-- Verify that the temporary file was cleaned up from disk
local file_exists = vim.uv.fs_stat(current_name) ~= nil
support.expect_equal('Scratchpad file deleted on wipeout', file_exists, false)

-- Cleanup temp directory
vim.fn.delete(temp_dir, 'rf')

support.flush()
