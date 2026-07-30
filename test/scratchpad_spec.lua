local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
local scratchpad = require('user.scratchpad')

-- 1. Mock a buffer and test scratchpad opening and temporary file generation
local temp_dir = vim.fn.tempname()
vim.fn.mkdir(temp_dir, 'p')
temp_dir = vim.uv.fs_realpath(temp_dir) or vim.fs.normalize(temp_dir)
vim.fn.writefile({ '' }, temp_dir .. '/.root')

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

-- 3. Test Java classpath resolution prefers the matching jdtls project client
local original_system = vim.fn.system
local original_get_clients = vim.lsp.get_clients
local recorded_cmd = nil
local requested_scopes = {}
local parent_dir = vim.fs.dirname(temp_dir)

vim.fn.system = function(cmd)
  recorded_cmd = cmd
  return 'mock output'
end

vim.lsp.get_clients = function(opts)
  if opts and opts.name == 'jdtls' then
    return {
      {
        name = 'jdtls',
        config = { root_dir = parent_dir },
        request = function(self, method, params, cb, req_bufnr)
          if params.command == 'java.project.isTestFile' then
            cb(nil, false)
            return
          end
          if params.command == 'java.project.getClasspaths' then
            cb(nil, { classpaths = { '/cp/wrong-parent' } })
            return
          end
          cb('unexpected command', nil)
        end,
      },
      {
        name = 'jdtls',
        config = { root_dir = temp_dir },
        request = function(self, method, params, cb, req_bufnr)
          if params.command == 'java.project.isTestFile' then
            cb(nil, false)
            return
          end
          if params.command == 'java.project.getClasspaths' then
            local opts_json = vim.json.decode(params.arguments[2])
            table.insert(requested_scopes, opts_json.scope)
            cb(nil, { classpaths = { '/cp/correct-project', '/cp/dependency' } })
            return
          end
          cb('unexpected command', nil)
        end,
      },
    }
  end

  return original_get_clients(opts)
end

run_scratchpad(current_buf, current_name, 'java')
vim.wait(1000, function()
  return recorded_cmd ~= nil
end)

vim.fn.system = original_system
vim.lsp.get_clients = original_get_clients

support.expect_true('Scratchpad uses classpath from matching jdtls client', recorded_cmd ~= nil and recorded_cmd:find('/cp/correct-project', 1, true) ~= nil)
support.expect_true('Scratchpad skips parent jdtls client classpath', recorded_cmd ~= nil and recorded_cmd:find('/cp/wrong-parent', 1, true) == nil)
support.expect_equal('Scratchpad requests runtime classpath for non-test file', requested_scopes[1], 'runtime')

-- Wipe out the buffer to trigger BufWipeout autocmd cleanup
vim.cmd('bwipeout!')

-- Verify that the temporary file was cleaned up from disk
local file_exists = vim.uv.fs_stat(current_name) ~= nil
support.expect_equal('Scratchpad file deleted on wipeout', file_exists, false)

-- Cleanup temp directory
vim.fn.delete(temp_dir, 'rf')

support.flush()
