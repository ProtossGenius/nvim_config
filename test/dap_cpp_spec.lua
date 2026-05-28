local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

local user_dap = require('user.dap')
local temp_root = vim.fn.tempname()
vim.fn.mkdir(temp_root .. '/src', 'p')
temp_root = vim.uv.fs_realpath(temp_root) or vim.fs.normalize(temp_root)
vim.cmd('cd ' .. vim.fn.fnameescape(temp_root))

vim.fn.writefile({
  'cmake_minimum_required(VERSION 3.20)',
  'project(cpp_dap_demo)',
  'add_executable(cpp_dap_demo src/main.cpp)',
}, temp_root .. '/CMakeLists.txt')
vim.fn.writefile({
  '#include <iostream>',
  'int main() { std::cout << "hello"; return 0; }',
}, temp_root .. '/src/main.cpp')

local source_path = vim.fs.normalize(temp_root .. '/src/main.cpp')
local config_path = vim.fs.normalize(temp_root .. '/.nvim-dap.json')
vim.cmd('edit ' .. vim.fn.fnameescape(source_path))
user_dap.edit_config(0)

local generated = vim.json.decode(table.concat(vim.fn.readfile(config_path), '\n'))
support.expect_equal('cpp dap detects cmake build tool', generated._detected.buildTool, 'cmake')
support.expect_equal('cpp dap creates launch config', generated.configurations[1].request, 'launch')
support.expect_equal('cpp dap launch uses lldb', generated.configurations[1].type, 'lldb')
support.expect_equal('cpp dap attach config exists', generated.configurations[2].request, 'attach')
support.expect_equal('cpp dap attach query defaults to target name', generated.configurations[2].processQuery, 'cpp_dap_demo')

generated.configurations = {
  {
    name = 'attach-process',
    type = 'lldb',
    request = 'attach',
    processQuery = 'cpp_dap_demo',
  },
}
vim.fn.writefile(vim.split(vim.json.encode(generated), '\n', { plain = true }), config_path)

local captured
local select_calls = 0
local original_dap = package.loaded['dap']
local original_input = vim.ui.input
local original_select = vim.ui.select
local original_system = vim.system

package.loaded['dap'] = {
  adapters = {},
  run = function(config)
    captured = config
  end,
  toggle_breakpoint = function() end,
}

vim.ui.input = function(_, callback)
  callback('cpp_dap_demo')
end
vim.ui.select = function(items, _, callback)
  select_calls = select_calls + 1
  callback(items[2])
end
vim.system = function(cmd, opts)
  local joined = table.concat(cmd, ' ')
  if joined:find('xcrun %-%-find lldb%-dap', 1, false) then
    return {
      wait = function()
        return {
          code = 0,
          stdout = '/usr/bin/lldb-dap\n',
        }
      end,
    }
  end

  if joined:find('ps %-axo pid=,command=', 1, false) then
    return {
      wait = function()
        return {
          code = 0,
          stdout = '1001 /tmp/cpp_dap_demo --tag one\n1002 /tmp/cpp_dap_demo --tag two\n',
        }
      end,
    }
  end

  if joined:find('ps %-M %-p 1001', 1, false) then
    return {
      wait = function()
        return {
          code = 0,
          stdout = 'HEADER\n1\n2\n',
        }
      end,
    }
  end

  if joined:find('ps %-M %-p 1002', 1, false) then
    return {
      wait = function()
        return {
          code = 0,
          stdout = 'HEADER\n1\n2\n3\n',
        }
      end,
    }
  end

  return original_system(cmd, opts)
end

user_dap.start(0)

support.expect_equal('cpp dap attach picks selected process pid', captured.pid, 1002)
support.expect_equal('cpp dap attach keeps lldb type', captured.type, 'lldb')
support.expect_equal('cpp dap attach clears process query after selection', captured.processQuery, nil)
support.expect_equal('cpp dap attach shows picker for multiple matches', select_calls, 1)

vim.ui.input = original_input
vim.ui.select = original_select
vim.system = original_system
package.loaded['dap'] = original_dap

vim.cmd('bdelete!')
vim.fn.delete(temp_root, 'rf')

support.flush()
