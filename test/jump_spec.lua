local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
local jump = require('user.jump')

local temp_root = vim.fn.tempname()
vim.fn.mkdir(temp_root .. '/src/main/java/com/example', 'p')
temp_root = vim.uv.fs_realpath(temp_root) or vim.fs.normalize(temp_root)

local java_path = vim.fs.normalize(temp_root .. '/src/main/java/com/example/App.java')
vim.fn.writefile({
  'package com.example;',
  '',
  'public class App {',
  '  private String label;',
  '',
  '  public void run() {',
  '    System.out.println(label);',
  '  }',
  '}',
}, java_path)

vim.cmd('cd ' .. vim.fn.fnameescape(temp_root))

local path_ref = jump.parse_reference('src/main/java/com/example/App.java:6')
support.expect_equal('jump parses path refs', path_ref.kind, 'path')

local java_ref = jump.parse_reference('com.example.App#run')
support.expect_equal('jump parses java refs', java_ref.kind, 'java-reference')

local stack_ref = jump.parse_reference('at com.example.App.run(App.java:6)')
support.expect_equal('jump parses java stack refs', stack_ref.kind, 'java-stack')

local ok_path = jump.jump_reference('src/main/java/com/example/App.java:6', { path = temp_root })
support.expect_true('jump opens path refs', ok_path)
support.expect_equal('jump path opens right file', vim.api.nvim_buf_get_name(0), java_path)
support.expect_equal('jump path opens right line', vim.api.nvim_win_get_cursor(0)[1], 6)

local ok_java = jump.jump_reference('com.example.App#run', { path = temp_root })
support.expect_true('jump opens java refs', ok_java)
support.expect_equal('jump java ref line', vim.api.nvim_win_get_cursor(0)[1], 6)

local ok_stack = jump.jump_reference('at com.example.App.run(App.java:6)', { path = temp_root })
support.expect_true('jump opens java stack refs', ok_stack)
support.expect_equal('jump stack line', vim.api.nvim_win_get_cursor(0)[1], 6)

vim.cmd('edit ' .. vim.fn.fnameescape(java_path))
vim.api.nvim_win_set_cursor(0, { 6, 15 })
support.expect_equal('copy reference uses java member form', jump.copy_reference(), 'com.example.App#run')

vim.cmd('enew!')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'at com.example.App.run(App.java:6)' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
support.feed('<S-f>')
support.expect_equal('shift-f stack jump opens java file', vim.api.nvim_buf_get_name(0), java_path)
support.expect_equal('shift-f stack jump line', vim.api.nvim_win_get_cursor(0)[1], 6)

vim.cmd('bdelete!')
vim.fn.delete(temp_root, 'rf')

support.flush()
