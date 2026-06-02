local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

-- Verify that the keymaps are loaded via init.lua / keymaps.lua
local function has_map(lhs)
  local info = vim.fn.maparg(lhs, 'n', false, true)
  return type(info) == 'table' and not vim.tbl_isempty(info)
end

support.expect_true('dap keymap has toggle breakpoint', has_map('<leader>db'))
support.expect_true('dap keymap has conditional breakpoint', has_map('<leader>dB'))
support.expect_true('dap keymap has continue', has_map('<leader>dc'))
support.expect_true('dap keymap has step over', has_map('<leader>dn'))
support.expect_true('dap keymap has step into', has_map('<leader>di'))
support.expect_true('dap keymap has step out', has_map('<leader>do'))
support.expect_true('dap keymap has REPL console', has_map('<leader>dr'))
support.expect_true('dap keymap has scopes sidebar', has_map('<leader>dl'))
support.expect_true('dap keymap has stack sidebar', has_map('<leader>dt'))
support.expect_true('dap keymap has start config', has_map('<leader>Dc'))
support.expect_true('dap keymap has edit config', has_map('<leader>De'))

support.expect_equal('dap command keeps DebugStart', vim.fn.exists(':DebugStart'), 2)
support.expect_equal('dap command keeps DebugConfigEdit', vim.fn.exists(':DebugConfigEdit'), 2)
support.expect_equal('dap command keeps DebugToggleBreakpoint', vim.fn.exists(':DebugToggleBreakpoint'), 2)
support.expect_equal('dap command adds DapAttach', vim.fn.exists(':DapAttach'), 2)

support.flush()
