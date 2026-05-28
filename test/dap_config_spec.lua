local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
local user_dap = require('user.dap')

local temp_root = vim.fn.tempname()
vim.fn.mkdir(temp_root, 'p')
temp_root = vim.uv.fs_realpath(temp_root) or vim.fs.normalize(temp_root)
vim.cmd('cd ' .. vim.fn.fnameescape(temp_root))

local source_path = vim.fs.normalize(temp_root .. '/main.py')
vim.fn.writefile({ 'print("hello")' }, source_path)
vim.cmd('edit ' .. vim.fn.fnameescape(source_path))

local config_path = vim.fs.normalize(temp_root .. '/.nvim-dap.json')
vim.fn.writefile(vim.split(vim.json.encode({
  configurations = {
    {
      name = 'Run current file',
      type = 'python',
      request = 'launch',
      program = '${file}',
      cwd = '${projectRoot}',
      args = { '--flag' },
    },
  },
}), '\n', { plain = true }), config_path)

local captured
local original_dap = package.loaded['dap']
package.loaded['dap'] = {
  run = function(config)
    captured = config
  end,
  toggle_breakpoint = function() end,
}

user_dap.start(0)

support.expect_true('dap start passes config to dap.run', captured ~= nil)
support.expect_equal('dap start expands file placeholder', captured.program, source_path)
support.expect_equal('dap start expands project root placeholder', captured.cwd, temp_root)
support.expect_equal('dap start preserves args array', captured.args[1], '--flag')

package.loaded['dap'] = original_dap
vim.cmd('bdelete!')
vim.fn.delete(temp_root, 'rf')

support.flush()
