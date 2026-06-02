local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

package.loaded['user.java'] = nil
local user_java = require('user.java')
local original_cmd = vim.cmd
local commands = {}

-- Create a mock parent project directory with two submodules: core and api
local parent_dir = vim.fn.tempname()
vim.fn.mkdir(parent_dir, 'p')

-- Parent marker to simulate monorepo/submodules
vim.fn.writefile({ 'true' }, parent_dir .. '/.root')

-- Module 1: core
local core_dir = parent_dir .. '/core'
local core_java_dir = core_dir .. '/src/main/java/com/example/core'
vim.fn.mkdir(core_java_dir, 'p')
vim.fn.writefile({ '<project/>' }, core_dir .. '/pom.xml')
local core_file = core_java_dir .. '/Core.java'
vim.fn.writefile({
  'package com.example.core;',
  'class Core {}',
}, core_file)

-- Module 2: api
local api_dir = parent_dir .. '/api'
local api_java_dir = api_dir .. '/src/main/java/com/example/api'
vim.fn.mkdir(api_java_dir, 'p')
vim.fn.writefile({ '<project/>' }, api_dir .. '/pom.xml')
local api_file = api_java_dir .. '/Api.java'
vim.fn.writefile({
  'package com.example.api;',
  'class Api {}',
}, api_file)

vim.cmd = function(command)
  table.insert(commands, command)
end

-- Simulate opening core's Java file first
local core_buf = vim.fn.bufadd(core_file)
vim.fn.bufload(core_buf)
vim.bo[core_buf].filetype = 'java'
vim.api.nvim_buf_set_name(core_buf, core_file)

-- Try autostart logic for core
local core_started = user_java.ensure_project_jdtls(core_dir)
support.expect_true('java autostart detects core project', core_started)

-- Simulate opening api's Java file next
local api_buf = vim.fn.bufadd(api_file)
vim.fn.bufload(api_buf)
vim.bo[api_buf].filetype = 'java'
vim.api.nvim_buf_set_name(api_buf, api_file)

-- Try autostart logic for api
local api_started = user_java.ensure_project_jdtls(api_dir)
support.expect_true('java autostart detects api project independently', api_started)

-- Check that JDTLS start command is scheduled/run for both modules
vim.wait(300)

local lsp_start_count = 0
for _, cmd in ipairs(commands) do
  if cmd == 'silent! LspStart jdtls' then
    lsp_start_count = lsp_start_count + 1
  end
end

support.expect_true('LspStart jdtls is triggered for both submodules', lsp_start_count >= 2)

-- Test project_root prioritization of _G.initial_cwd
local original_initial_cwd = _G.initial_cwd
_G.initial_cwd = parent_dir
vim.fn.writefile({ '<project/>' }, parent_dir .. '/pom.xml')

local resolved_root = user_java._test.project_root(core_file)
support.expect_equal('project_root prioritizes initial_cwd when it has pom.xml', vim.fs.normalize(resolved_root), vim.fs.normalize(parent_dir))

_G.initial_cwd = original_initial_cwd

-- Cleanup
vim.cmd = original_cmd
vim.fn.delete(parent_dir, 'rf')

support.flush()
