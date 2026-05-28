local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

package.loaded['user.dap_keymaps'] = nil

local dap_keymaps = require('user.dap_keymaps')
dap_keymaps.setup()

local function has_map(lhs)
  local info = vim.fn.maparg(lhs, 'n', false, true)
  return type(info) == 'table' and not vim.tbl_isempty(info)
end

support.expect_true('dap keymap has toggle breakpoint', has_map('<leader>db'))
support.expect_true('dap keymap has continue', has_map('<leader>dc'))
support.expect_true('dap keymap has next', has_map('<leader>dn'))
support.expect_true('dap keymap has project step', has_map('<leader>ds'))
support.expect_true('dap keymap has raw step', has_map('<leader>dS'))
support.expect_true('dap keymap has project step out', has_map('<leader>du'))
support.expect_true('dap keymap has raw step out', has_map('<leader>dU'))
support.expect_true('dap keymap has output panel', has_map('<leader>do'))
support.expect_true('dap keymap has locals panel', has_map('<leader>dl'))
support.expect_true('dap keymap has eval popup', has_map('<leader>de'))
support.expect_true('dap keymap has display add popup', has_map('<leader>da'))
support.expect_true('dap keymap has display list popup', has_map('<leader>dd'))
support.expect_true('dap keymap has stack popup', has_map('<leader>dt'))
support.expect_true('dap keymap has start config on upper D', has_map('<leader>Dc'))
support.expect_true('dap keymap has edit config on upper D', has_map('<leader>De'))
support.expect_true('dap keymap has enter repeat mapping', has_map('<CR>'))
support.expect_true('dap keymap removed command panel toggle', not has_map('<leader>dm'))

support.flush()
