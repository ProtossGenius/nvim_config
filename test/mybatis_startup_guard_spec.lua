local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

vim.wait(500)
support.expect_true('mybatis not loaded for empty startup buffer', package.loaded['mybatis-xml'] == nil)
support.expect_true('mybatis virtual sync not loaded for empty startup buffer', package.loaded['mybatis-xml.virtual.sync'] == nil)

local user_mybatis = require('user.mybatis')
local sync = user_mybatis.patch_virtual_sync()

local original_cwd = vim.fn.getcwd()
local original_find = vim.fs.find
local temp_root = vim.fn.tempname()
local non_java_root = temp_root .. '/non-java'
local java_root = temp_root .. '/java'
vim.fn.mkdir(non_java_root, 'p')
vim.fn.mkdir(java_root, 'p')
vim.fn.writefile({ '<project />' }, java_root .. '/pom.xml')

local find_called = false
vim.fs.find = function(_, opts)
  if opts and opts.type == 'file' and not opts.upward then
    find_called = true
  end
  return {}
end

vim.cmd('cd ' .. vim.fn.fnameescape(non_java_root))
sync.generate_all()
support.expect_true('mybatis startup scan skips non-java cwd', not find_called)

find_called = false
vim.cmd('cd ' .. vim.fn.fnameescape(java_root))
sync.generate_all()
support.expect_true('mybatis startup scan keeps java project cwd', find_called)

vim.fs.find = original_find
vim.cmd('cd ' .. vim.fn.fnameescape(original_cwd))
vim.fn.delete(temp_root, 'rf')

support.flush()
