local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

package.loaded['user.java'] = nil

local user_java = require('user.java')
local original_cmd = vim.cmd
local commands = {}

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

support.expect_true('java autostart ignores non-java project', not user_java.ensure_project_jdtls(vim.fn.tempname()))
support.expect_true('java autostart detects java project', user_java.ensure_project_jdtls(root))
vim.wait(300)
local app_buf = vim.fn.bufnr(java_dir .. '/App.java')
support.expect_equal('java autostart sets filetype to java', vim.bo[app_buf].filetype, 'java')

vim.cmd = original_cmd
vim.fn.delete(root, 'rf')

support.flush()
