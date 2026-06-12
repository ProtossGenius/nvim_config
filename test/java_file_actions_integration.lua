local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
local file_actions = require('user.file_actions')

local project_root = vim.fs.normalize(vim.env.NVIM_TEST_JAVA_PROJECT or (vim.fn.stdpath('config') .. '/test-projects/java17-spring-demo/core'))
local java_dir = project_root .. '/src/main/java/com/example/demo'
local suffix = tostring(os.time())
local old_class = 'NvimRenameSpec' .. suffix
local new_class = 'NvimRenameSpecRenamed' .. suffix
local old_path = java_dir .. '/' .. old_class .. '.java'
local new_path = java_dir .. '/' .. new_class .. '.java'

vim.fn.writefile({
  'package com.example.demo;',
  '',
  'public class ' .. old_class .. ' {',
  '  public String label() {',
  '    return "' .. old_class .. '";',
  '  }',
  '}',
}, old_path)

vim.cmd('edit ' .. vim.fn.fnameescape(old_path))

local attached = vim.wait(120000, function()
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    if client.name == 'jdtls' then
      return true
    end
  end
  return false
end, 200)

support.expect_true('java integration jdtls attached', attached)
support.expect_true('java integration rename succeeds', file_actions.rename_path(old_path, { new_name = new_class .. '.java' }))
support.expect_true('java integration new file exists', vim.uv.fs_stat(new_path) ~= nil)
support.expect_true('java integration old file removed', vim.uv.fs_stat(old_path) == nil)

vim.wait(1000)
local new_contents = table.concat(vim.fn.readfile(new_path), '\n')
support.expect_true('java integration class renamed on disk', new_contents:find('class ' .. new_class, 1, true) ~= nil)
support.expect_true('java integration old class removed on disk', new_contents:find('class ' .. old_class, 1, true) == nil)

vim.cmd('bdelete!')
vim.fn.delete(new_path)

support.flush()
