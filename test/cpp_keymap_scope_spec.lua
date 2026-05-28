local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

local temp_root = vim.fn.tempname()
vim.fn.mkdir(temp_root .. '/src', 'p')
vim.fn.writefile({
  'cmake_minimum_required(VERSION 3.20)',
  'project(scope_demo)',
  'add_executable(scope_demo src/main.cpp)',
}, temp_root .. '/CMakeLists.txt')
vim.fn.writefile({ 'int main() { return 0; }' }, temp_root .. '/src/main.cpp')

local other_root = vim.fn.tempname()
vim.fn.mkdir(other_root, 'p')
vim.fn.writefile({ 'int main() { return 0; }' }, other_root .. '/main.cpp')

local function has_buffer_map(lhs)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, 'n')) do
    if map.lhs == lhs then
      return true
    end
  end
  return false
end

local function has_global_map(lhs)
  local info = vim.fn.maparg(lhs, 'n', false, true)
  return type(info) == 'table' and not vim.tbl_isempty(info)
end

vim.cmd('edit ' .. vim.fn.fnameescape(vim.fs.normalize(temp_root .. '/src/main.cpp')))
vim.bo.filetype = 'cpp'
vim.api.nvim_exec_autocmds('FileType', { buffer = 0, modeline = false })
support.expect_true('cpp project buffer gets M-y mapping', has_buffer_map('<M-y>'))
support.expect_true('global M-h keeps left split mapping', has_global_map('<M-h>'))

vim.cmd('edit ' .. vim.fn.fnameescape(vim.fs.normalize(other_root .. '/main.cpp')))
vim.bo.filetype = 'cpp'
vim.api.nvim_exec_autocmds('FileType', { buffer = 0, modeline = false })
support.expect_true('non project cpp buffer skips M-y mapping', not has_buffer_map('<M-y>'))

vim.fn.delete(temp_root, 'rf')
vim.fn.delete(other_root, 'rf')

support.flush()
