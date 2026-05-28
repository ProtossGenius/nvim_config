local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

package.loaded['user.dap_keymaps'] = nil

local dap_keymaps = require('user.dap_keymaps')
dap_keymaps.setup()

local function has_map(lhs)
  local info = vim.fn.maparg(lhs, 'n', false, true)
  return type(info) == 'table' and not vim.tbl_isempty(info)
end

support.expect_true('dap keymap has toggle breakpoint', has_map('<leader>db'))
support.expect_true('dap keymap has start config', has_map('<leader>dc'))
support.expect_true('dap keymap has edit config', has_map('<leader>de'))
support.expect_true('dap keymap has output panel', has_map('<leader>do'))
support.expect_true('dap keymap has command panel', has_map('<leader>dm'))
support.expect_true('dap keymap has locals panel', has_map('<leader>dl'))
support.expect_true('dap keymap removed quick mode toggle', not has_map('<leader>dq'))

support.flush()
