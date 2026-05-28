local M = {}

local opts = { noremap = true, silent = true }
local state = {
  active = false,
  last_thread_id = nil,
  pending_step = nil,
  project_root = nil,
}
local listeners_attached = false

local function normalize(path)
  if not path or path == '' then
    return nil
  end
  return vim.fs.normalize(path)
end

local function starts_with_path(path, root)
  return path == root or path:sub(1, #root + 1) == root .. '/'
end

local function current_session()
  local ok, dap = pcall(require, 'dap')
  if not ok or not dap.session then
    return nil
  end
  return dap.session()
end

local function request_step(command)
  local session = current_session()
  if not session or not state.last_thread_id then
    return false
  end

  session:request(command, {
    threadId = state.last_thread_id,
  }, function(err)
    if err then
      state.pending_step = nil
      vim.notify('DAP step failed: ' .. tostring(err), vim.log.levels.ERROR)
    end
  end)
  return true
end

local function raw_step(command)
  local dap = require('dap')
  if command == 'next' then
    dap.step_over()
  elseif command == 'stepOut' then
    dap.step_out()
  else
    dap.step_into()
  end
end

local function project_relative_step(command)
  if request_step(command) then
    state.pending_step = {
      command = command,
      remaining = 50,
    }
    return
  end

  raw_step(command)
end

M.quick_mode_mappings = {
  n = {
    action = function() project_relative_step('next') end,
    desc = 'DAP quick: next line (project only)',
  },
  N = {
    action = function() raw_step('next') end,
    desc = 'DAP quick: next line',
  },
  s = {
    action = function() project_relative_step('stepIn') end,
    desc = 'DAP quick: step into (project only)',
  },
  S = {
    action = function() raw_step('stepIn') end,
    desc = 'DAP quick: step into',
  },
  u = {
    action = function() project_relative_step('stepOut') end,
    desc = 'DAP quick: step out (project only)',
  },
  U = {
    action = function() raw_step('stepOut') end,
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

  for lhs, _ in pairs(M.quick_mode_mappings) do
    pcall(vim.keymap.del, 'n', lhs)
  end
  pcall(vim.keymap.del, 'n', 'q')

  state.active = false
  state.last_thread_id = nil
  state.pending_step = nil
  state.project_root = nil
  vim.notify('DAP quick mode off', vim.log.levels.INFO)
end

function M.enter_quick_mode()
  if state.active then
    return
  end

  for lhs, spec in pairs(M.quick_mode_mappings) do
    vim.keymap.set('n', lhs, spec.action, {
      noremap = true,
      silent = true,
      desc = spec.desc,
    })
  end
  vim.keymap.set('n', 'q', M.exit_quick_mode, {
    noremap = true,
    silent = true,
    desc = 'DAP quick: exit mode',
  })

  state.active = true
  vim.notify('DAP quick mode on', vim.log.levels.INFO)
end

function M.toggle_quick_mode()
  if state.active then
    M.exit_quick_mode()
  else
    M.enter_quick_mode()
  end
end

function M.is_quick_mode()
  return state.active
end

function M.set_project_root(root)
  state.project_root = normalize(root)
end

function M.step_into_project()
  project_relative_step('stepIn')
end

function M.step_into_raw()
  raw_step('stepIn')
end

function M.handle_stopped(_, body)
  state.last_thread_id = body and body.threadId or state.last_thread_id
  local pending = state.pending_step
  if not pending then
    return
  end

  local session = current_session()
  if not session or not state.last_thread_id or not state.project_root then
    state.pending_step = nil
    return
  end

  session:request('stackTrace', {
    threadId = state.last_thread_id,
    startFrame = 0,
    levels = 1,
  }, function(err, response)
    if err then
      state.pending_step = nil
      return
    end

    local frame = response and response.stackFrames and response.stackFrames[1]
    local source_path = frame and frame.source and normalize(frame.source.path)
    if source_path
      and not starts_with_path(source_path, state.project_root)
      and pending.remaining > 0
    then
      pending.remaining = pending.remaining - 1
      request_step(pending.command)
      return
    end

    state.pending_step = nil
  end)
end

function M.ensure_listeners()
  if listeners_attached then
    return true
  end

  local ok, dap = pcall(require, 'dap')
  if not ok then
    return false
  end

  dap.listeners.after.event_stopped.user_dap_quick_mode = function(session, body)
    vim.schedule(function()
      M.handle_stopped(session, body)
    end)
  end
  dap.listeners.after.event_initialized.user_dap_quick_mode = function()
    vim.schedule(M.enter_quick_mode)
  end
  dap.listeners.before.event_continued.user_dap_quick_mode = function()
    state.pending_step = nil
    state.last_thread_id = nil
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
