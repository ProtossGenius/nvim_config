local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

local function map_info(lhs)
  local info = vim.fn.maparg(lhs, 'n', false, true)
  if type(info) ~= 'table' or vim.tbl_isempty(info) then
    return nil
  end
  return info
end

local function expect_not_dap_map(name, lhs, desc)
  local info = map_info(lhs)
  support.expect_true(name, not info or info.desc ~= desc)
end

expect_not_dap_map('dap keymap disables toggle breakpoint by default', '<leader>db', 'Debug: Toggle breakpoint')
expect_not_dap_map('dap keymap disables continue by default', '<leader>dc', 'Debug: Continue')
expect_not_dap_map('dap keymap disables next by default', '<leader>dn', 'Debug: Next')
expect_not_dap_map('dap keymap disables project step by default', '<leader>ds', 'Debug: Step to next project code')
expect_not_dap_map('dap keymap disables raw step by default', '<leader>dS', 'Debug: Step into raw')
expect_not_dap_map('dap keymap disables project step out by default', '<leader>du', 'Debug: Step out to project code')
expect_not_dap_map('dap keymap disables raw step out by default', '<leader>dU', 'Debug: Step out raw')
expect_not_dap_map('dap keymap disables output panel by default', '<leader>do', 'Debug: Toggle output panel')
expect_not_dap_map('dap keymap disables locals panel by default', '<leader>dl', 'Debug: Toggle locals panel')
expect_not_dap_map('dap keymap disables eval popup by default', '<leader>de', 'Debug: Eval popup')
expect_not_dap_map('dap keymap disables display add popup by default', '<leader>da', 'Debug: Add display popup')
expect_not_dap_map('dap keymap disables display list popup by default', '<leader>dd', 'Debug: Show displays')
expect_not_dap_map('dap keymap disables stack popup by default', '<leader>dt', 'Debug: Show stack popup')
expect_not_dap_map('dap keymap disables project start by default', '<leader>Dc', 'Debug: Start from project config')
expect_not_dap_map('dap keymap disables config edit by default', '<leader>De', 'Debug: Edit project config')
expect_not_dap_map('dap keymap leaves enter unmapped by default', '<CR>', 'Repeat last DAP action or enter')
support.expect_equal('dap command keeps DebugStart', vim.fn.exists(':DebugStart'), 2)
support.expect_equal('dap command keeps DebugConfigEdit', vim.fn.exists(':DebugConfigEdit'), 2)
support.expect_equal('dap command keeps DebugToggleBreakpoint', vim.fn.exists(':DebugToggleBreakpoint'), 2)
support.expect_equal('dap command adds DapAttach', vim.fn.exists(':DapAttach'), 2)

support.flush()
