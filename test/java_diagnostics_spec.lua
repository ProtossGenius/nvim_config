local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

local project_root = vim.fn.stdpath('config') .. '/test-projects/java17-spring-demo'
local temp_file = project_root .. '/core/src/main/java/com/example/demo/DiagnosticsProbe.java'

vim.fn.writefile({
  'package com.example.demo;',
  '',
  'public class DiagnosticsProbe {',
  '  void run() {',
  '    User1 missing = null;',
  '  }',
  '}',
}, temp_file)

_G.initial_cwd = project_root
vim.cmd('cd ' .. vim.fn.fnameescape(_G.initial_cwd))
vim.cmd('edit ' .. vim.fn.fnameescape(temp_file))
vim.bo.swapfile = false

local attached = vim.wait(60000, function()
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    if client.name == 'jdtls' then
      return true
    end
  end
  return false
end, 200)

support.expect_true('java diagnostics client attached', attached)

local diagnostics = {}
local diagnostics_ready = vim.wait(10000, function()
  diagnostics = vim.diagnostic.get(0)
  for _, diagnostic in ipairs(diagnostics) do
    if diagnostic.message and diagnostic.message:find('User1', 1, true) then
      return true
    end
  end
  return false
end, 200)

support.expect_true('java diagnostics published', diagnostics_ready)
support.expect_true('java diagnostics contain unresolved User1', diagnostics_ready)

vim.cmd('bdelete!')
vim.fn.delete(temp_file)
support.flush()
