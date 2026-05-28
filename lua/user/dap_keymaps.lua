local M = {}

local opts = { noremap = true, silent = true }
local state = {
  active = false,
  bufnr = nil,
}
local listeners_attached = false

M.quick_mode_mappings = {
  n = {
    action = function() require('dap').step_over() end,
    desc = 'DAP quick: next line',
  },
  s = {
    action = function() require('dap').step_into() end,
    desc = 'DAP quick: step into',
  },
  u = {
    action = function() require('dap').step_out() end,
    desc = 'DAP quick: step out',
  },
  c = {
    action = function() require('dap').continue() end,
    desc = 'DAP quick: continue',
  },
  b = {
    action = function() require('dap').toggle_breakpoint() end,
    desc = 'DAP quick: toggle breakpoint',
  },
}

local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, vim.tbl_extend('force', opts, { desc = desc }))
end

function M.exit_quick_mode()
  if not state.active then
    return
  end

  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    for lhs, _ in pairs(M.quick_mode_mappings) do
      pcall(vim.keymap.del, 'n', lhs, { buffer = state.bufnr })
    end
    pcall(vim.keymap.del, 'n', 'q', { buffer = state.bufnr })
  end

  state.active = false
  state.bufnr = nil
  vim.notify('DAP quick mode off', vim.log.levels.INFO)
end

function M.enter_quick_mode(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if state.active and state.bufnr == bufnr then
    return
  end

  M.exit_quick_mode()
  for lhs, spec in pairs(M.quick_mode_mappings) do
    vim.keymap.set('n', lhs, spec.action, {
      buffer = bufnr,
      noremap = true,
      silent = true,
      desc = spec.desc,
    })
  end
  vim.keymap.set('n', 'q', M.exit_quick_mode, {
    buffer = bufnr,
    noremap = true,
    silent = true,
    desc = 'DAP quick: exit mode',
  })

  state.active = true
  state.bufnr = bufnr
  vim.notify('DAP quick mode on', vim.log.levels.INFO)
end

function M.toggle_quick_mode()
  if state.active then
    M.exit_quick_mode()
  else
    M.enter_quick_mode(0)
  end
end

function M.is_quick_mode()
  return state.active
end

function M.ensure_listeners()
  if listeners_attached then
    return true
  end

  local ok, dap = pcall(require, 'dap')
  if not ok then
    return false
  end

  dap.listeners.after.event_stopped.user_dap_quick_mode = function()
    vim.schedule(function()
      M.enter_quick_mode(vim.api.nvim_get_current_buf())
    end)
  end
  dap.listeners.before.event_continued.user_dap_quick_mode = function()
    vim.schedule(M.exit_quick_mode)
  end
  dap.listeners.before.event_exited.user_dap_quick_mode = function()
    vim.schedule(M.exit_quick_mode)
  end
  dap.listeners.before.event_terminated.user_dap_quick_mode = function()
    vim.schedule(M.exit_quick_mode)
  end
  dap.listeners.before.disconnect.user_dap_quick_mode = function()
    vim.schedule(M.exit_quick_mode)
  end
  listeners_attached = true
  return true
end

function M.setup()
  map('n', '<leader>db', function()
    M.ensure_listeners()
    require('user.dap').toggle_breakpoint()
  end, 'Debug: Toggle breakpoint')
  map('n', '<leader>dc', function()
    M.ensure_listeners()
    require('user.dap').start()
  end, 'Debug: Start from project config')
  map('n', '<leader>de', function()
    M.ensure_listeners()
    require('user.dap').edit_config()
  end, 'Debug: Edit project config')
  map('n', '<leader>dq', function()
    M.ensure_listeners()
    M.toggle_quick_mode()
  end, 'Debug: Toggle quick mode')
end

return M
