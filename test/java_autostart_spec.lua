local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

package.loaded['user.java'] = nil

local user_java = require('user.java')
local original_cmd = vim.cmd
local original_echo = vim.api.nvim_echo
local commands = {}
local progress_messages = {}

local root = vim.fn.tempname()
local java_dir = root .. '/src/main/java/com/example'
vim.fn.mkdir(java_dir, 'p')
vim.fn.writefile({ '<project />' }, root .. '/pom.xml')
vim.fn.writefile({
  'package com.example;',
  'class App {}',
}, java_dir .. '/App.java')

vim.cmd = function(command)
  table.insert(commands, command)
end
vim.api.nvim_echo = function(chunks)
  table.insert(progress_messages, chunks[1] and chunks[1][1] or '')
end

local original_install = user_java.ensure_java_lsp_installed
user_java.ensure_java_lsp_installed = function()
  return '/tmp/java-lsp'
end

support.expect_true('java autostart ignores non-java project', not user_java.ensure_project_jdtls(vim.fn.tempname()))
support.expect_true('java autostart detects java project', user_java.ensure_project_jdtls(root))
vim.wait(300)
support.expect_true('java autostart issues LspStart jdtls', vim.tbl_contains(commands, 'silent! LspStart jdtls'))
support.expect_true('java autostart shows ensure progress', vim.tbl_contains(progress_messages, 'java-lsp: ensuring binary for ' .. vim.fn.fnamemodify(root, ':t') .. '...'))
support.expect_true('java autostart shows start progress', vim.tbl_contains(progress_messages, 'java-lsp: starting ' .. vim.fn.fnamemodify(root, ':t') .. '...'))

user_java.ensure_java_lsp_installed = original_install
vim.api.nvim_echo = original_echo
vim.cmd = original_cmd
vim.fn.delete(root, 'rf')

support.flush()
