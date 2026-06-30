local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

package.loaded['user.java'] = nil
local user_java = require('user.java')

-- Create a mock parent project directory with two submodules: core and api
local parent_dir = vim.fn.tempname()
vim.fn.mkdir(parent_dir, 'p')

-- Parent marker to simulate monorepo/submodules
vim.fn.writefile({ 'true' }, parent_dir .. '/.root')
vim.fn.writefile({ '<project/>' }, parent_dir .. '/pom.xml')

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

-- Test: project_root should resolve both submodule paths to the parent
local core_root = user_java._test.project_root(core_file)
local api_root = user_java._test.project_root(api_file)

support.expect_equal(
  'project_root resolves core submodule to parent',
  vim.fs.normalize(core_root),
  vim.fs.normalize(parent_dir)
)
support.expect_equal(
  'project_root resolves api submodule to parent',
  vim.fs.normalize(api_root),
  vim.fs.normalize(parent_dir)
)

-- Simulate opening core's Java file first
local core_buf = vim.fn.bufadd(core_file)
vim.fn.bufload(core_buf)
vim.api.nvim_buf_set_name(core_buf, core_file)
vim.bo[core_buf].filetype = 'java'

-- Trigger autostart for core
user_java.ensure_project_jdtls(core_dir)

-- Simulate opening api's Java file next
local api_buf = vim.fn.bufadd(api_file)
vim.fn.bufload(api_buf)
vim.api.nvim_buf_set_name(api_buf, api_file)
vim.bo[api_buf].filetype = 'java'

-- Trigger autostart for api
user_java.ensure_project_jdtls(api_dir)

-- Wait for JDTLS clients to initialize
vim.wait(8000, function()
  return #vim.lsp.get_clients({ name = 'jdtls' }) > 0
end, 200)

-- Wait another 2 seconds to make sure no duplicate starts late
vim.wait(2000)

-- Check number of JDTLS clients
local clients = vim.lsp.get_clients({ name = 'jdtls' })
print("Number of active JDTLS clients: " .. tostring(#clients))
for i, client in ipairs(clients) do
  print(string.format("Client %d root_dir: %s", i, client.config.root_dir))
end

-- We expect exactly 1 client
support.expect_equal('Only one JDTLS instance is started for the monorepo', #clients, 1)

-- Cleanup
vim.cmd('bdelete! ' .. core_buf)
vim.cmd('bdelete! ' .. api_buf)
for _, client in ipairs(clients) do
  pcall(function() client:terminate() end)
end
vim.fn.delete(parent_dir, 'rf')

support.flush()
