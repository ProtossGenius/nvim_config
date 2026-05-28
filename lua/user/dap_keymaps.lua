local M = {}

local opts = { noremap = true, silent = true }

local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, vim.tbl_extend('force', opts, { desc = desc }))
end

local function with_ui(callback)
  return function()
    local dap_ui = require('user.dap_ui')
    dap_ui.ensure_listeners()
    callback(dap_ui)
  end
end

function M.setup()
  map('n', '<leader>db', with_ui(function(dap_ui)
    dap_ui.toggle_breakpoint_here()
  end), 'Debug: Toggle breakpoint')
  map('n', '<leader>dc', with_ui(function(dap_ui)
    dap_ui.run_action('continue')
  end), 'Debug: Continue')
  map('n', '<leader>dn', with_ui(function(dap_ui)
    dap_ui.run_action('next')
  end), 'Debug: Next')
  map('n', '<leader>ds', with_ui(function(dap_ui)
    dap_ui.run_action('step_project')
  end), 'Debug: Step to next project code')
  map('n', '<leader>dS', with_ui(function(dap_ui)
    dap_ui.run_action('step_raw')
  end), 'Debug: Step into raw')
  map('n', '<leader>du', with_ui(function(dap_ui)
    dap_ui.run_action('out_project')
  end), 'Debug: Step out to project code')
  map('n', '<leader>dU', with_ui(function(dap_ui)
    dap_ui.run_action('out_raw')
  end), 'Debug: Step out raw')
  map('n', '<leader>do', with_ui(function(dap_ui)
    dap_ui.toggle_output()
  end), 'Debug: Toggle output panel')
  map('n', '<leader>dl', with_ui(function(dap_ui)
    dap_ui.toggle_locals()
  end), 'Debug: Toggle locals panel')
  map('n', '<leader>de', with_ui(function(dap_ui)
    dap_ui.open_eval_popup()
  end), 'Debug: Eval popup')
  map('n', '<leader>da', with_ui(function(dap_ui)
    dap_ui.open_display_add_popup()
  end), 'Debug: Add display popup')
  map('n', '<leader>dd', with_ui(function(dap_ui)
    dap_ui.open_display_list()
  end), 'Debug: Show displays')
  map('n', '<leader>dt', with_ui(function(dap_ui)
    dap_ui.open_stack_popup()
  end), 'Debug: Show stack popup')

  map('n', '<leader>Dc', with_ui(function()
    require('user.dap').start()
  end), 'Debug: Start from project config')
  map('n', '<leader>De', with_ui(function()
    require('user.dap').edit_config()
  end), 'Debug: Edit project config')

  map('n', '<CR>', function()
    local dap_ui = require('user.dap_ui')
    if dap_ui.repeat_last_action() then
      return
    end
    vim.cmd('normal! <CR>')
  end, 'Repeat last DAP action or enter')
end

return M
