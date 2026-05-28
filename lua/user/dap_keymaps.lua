local M = {}

local opts = { noremap = true, silent = true }

local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, vim.tbl_extend('force', opts, { desc = desc }))
end

function M.setup()
  map('n', '<leader>db', function()
    require('user.dap_ui').ensure_listeners()
    require('user.dap').toggle_breakpoint()
  end, 'Debug: Toggle breakpoint')
  map('n', '<leader>dc', function()
    require('user.dap_ui').ensure_listeners()
    require('user.dap').start()
  end, 'Debug: Start from project config')
  map('n', '<leader>de', function()
    require('user.dap_ui').ensure_listeners()
    require('user.dap').edit_config()
  end, 'Debug: Edit project config')
  map('n', '<leader>do', function()
    require('user.dap_ui').ensure_listeners()
    require('user.dap_ui').toggle_output()
  end, 'Debug: Toggle output panel')
  map('n', '<leader>dm', function()
    require('user.dap_ui').ensure_listeners()
    require('user.dap_ui').toggle_command()
  end, 'Debug: Toggle command panel')
  map('n', '<leader>dl', function()
    require('user.dap_ui').ensure_listeners()
    require('user.dap_ui').toggle_locals()
  end, 'Debug: Toggle locals panel')
end

return M
