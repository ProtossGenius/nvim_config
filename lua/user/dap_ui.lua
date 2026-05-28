local M = {}

local PANEL_HEIGHT = 12

local state = {
  listeners_attached = false,
  panels = {
    output = { key = 'output', title = 'DAP Output', shown = false, lines = {} },
    command = { key = 'command', title = 'DAP Command', shown = false },
    locals = { key = 'locals', title = 'DAP Locals', shown = false, lines = { 'No locals yet.' } },
  },
  visible_order = {},
  last_command = nil,
  display_expressions = {},
  display_values = {},
  project_root = nil,
  current_thread_id = nil,
  current_frame_id = nil,
  pending_project_step = nil,
  last_visited_file = nil,
}

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

local function editor_size()
  local ui = vim.api.nvim_list_uis()[1]
  if not ui then
    return vim.o.columns, vim.o.lines
  end
  return ui.width, ui.height
end

local function is_panel_buf(bufnr)
  for _, panel in pairs(state.panels) do
    if panel.bufnr == bufnr then
      return true
    end
  end
  return false
end

local function set_panel_lines(panel, lines)
  panel.lines = vim.deepcopy(lines)
  if panel.bufnr and vim.api.nvim_buf_is_valid(panel.bufnr) then
    vim.bo[panel.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(panel.bufnr, 0, -1, false, panel.lines)
    vim.bo[panel.bufnr].modifiable = false
  end
end

local function append_panel_lines(panel, lines)
  if not lines or #lines == 0 then
    return
  end
  panel.lines = panel.lines or {}
  for _, line in ipairs(lines) do
    table.insert(panel.lines, line)
  end
  if panel.bufnr and vim.api.nvim_buf_is_valid(panel.bufnr) then
    vim.bo[panel.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(panel.bufnr, -1, -1, false, lines)
    vim.bo[panel.bufnr].modifiable = false
  end
end

local function command_panel()
  return state.panels.command
end

local function append_console(lines)
  local panel = command_panel()
  if not panel.bufnr or not vim.api.nvim_buf_is_valid(panel.bufnr) then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(panel.bufnr)
  local insert_at = math.max(line_count - 1, 0)
  vim.bo[panel.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(panel.bufnr, insert_at, insert_at, false, lines)
  vim.bo[panel.bufnr].modifiable = false
end

local function prompt_buffer_setup(bufnr)
  vim.bo[bufnr].buftype = 'prompt'
  vim.bo[bufnr].bufhidden = 'hide'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = 'user-dap-command'
  vim.bo[bufnr].modifiable = true
  vim.fn.prompt_setprompt(bufnr, '(dap) ')
end

local function create_panel_buffer(panel)
  if panel.bufnr and vim.api.nvim_buf_is_valid(panel.bufnr) then
    return panel.bufnr
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  panel.bufnr = bufnr
  vim.bo[bufnr].bufhidden = 'hide'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].buflisted = false

  if panel.key == 'command' then
    prompt_buffer_setup(bufnr)
  else
    vim.bo[bufnr].buftype = 'nofile'
    vim.bo[bufnr].filetype = 'user-dap-' .. panel.key
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, panel.lines or {})
    vim.bo[bufnr].modifiable = false
  end

  return bufnr
end

local function close_panel_window(panel)
  if panel.winid and vim.api.nvim_win_is_valid(panel.winid) then
    vim.api.nvim_win_close(panel.winid, true)
  end
  panel.winid = nil
end

local function layout_panels()
  local ordered = {}
  for _, key in ipairs(state.visible_order) do
    local panel = state.panels[key]
    if panel and panel.shown then
      table.insert(ordered, panel)
    end
  end

  for _, panel in pairs(state.panels) do
    if not panel.shown then
      close_panel_window(panel)
    end
  end

  if #ordered == 0 then
    return
  end

  local width, height = editor_size()
  local panel_height = math.min(PANEL_HEIGHT, math.max(8, math.floor(height * 0.25)))
  local row = math.max(0, height - panel_height - vim.o.cmdheight - 1)

  local base_width = math.floor(width / #ordered)
  local remainder = width - base_width * #ordered
  local col = 0

  for index, panel in ipairs(ordered) do
    local panel_width = base_width + (index <= remainder and 1 or 0)
    local bufnr = create_panel_buffer(panel)
    local config = {
      relative = 'editor',
      row = row,
      col = col,
      width = panel_width,
      height = panel_height,
      style = 'minimal',
      border = 'single',
      zindex = 40,
    }

    if panel.winid and vim.api.nvim_win_is_valid(panel.winid) then
      vim.api.nvim_win_set_config(panel.winid, config)
      vim.api.nvim_win_set_buf(panel.winid, bufnr)
    else
      panel.winid = vim.api.nvim_open_win(bufnr, false, config)
    end

    vim.wo[panel.winid].number = false
    vim.wo[panel.winid].relativenumber = false
    vim.wo[panel.winid].signcolumn = 'no'
    vim.wo[panel.winid].wrap = false
    vim.api.nvim_win_set_option(panel.winid, 'winbar', ' ' .. panel.title)
    col = col + panel_width
  end
end

local function show_panel(key)
  local panel = state.panels[key]
  if not panel or panel.shown then
    return
  end
  panel.shown = true
  table.insert(state.visible_order, key)
  create_panel_buffer(panel)
  layout_panels()
end

local function hide_panel(key)
  local panel = state.panels[key]
  if not panel or not panel.shown then
    return
  end
  panel.shown = false
  for index, value in ipairs(state.visible_order) do
    if value == key then
      table.remove(state.visible_order, index)
      break
    end
  end
  close_panel_window(panel)
  layout_panels()
end

local function toggle_panel(key)
  if state.panels[key].shown then
    hide_panel(key)
  else
    show_panel(key)
  end
end

local function session_request(command, arguments, callback)
  local session = current_session()
  if not session then
    callback('No active DAP session.')
    return
  end
  session:request(command, arguments, callback)
end

local function target_file_for_breakpoint()
  local path = normalize(state.last_visited_file)
  if path and vim.uv.fs_stat(path) then
    return path
  end

  local candidates = {}
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local cfg = vim.api.nvim_win_get_config(winid)
    if cfg.relative == '' then
      local bufnr = vim.api.nvim_win_get_buf(winid)
      local name = normalize(vim.api.nvim_buf_get_name(bufnr))
      if name and name ~= '' and vim.bo[bufnr].buftype == '' then
        local pos = vim.api.nvim_win_get_position(winid)
        table.insert(candidates, {
          path = name,
          row = pos[1],
          col = pos[2],
          line = vim.api.nvim_win_get_cursor(winid)[1],
        })
      end
    end
  end

  table.sort(candidates, function(left, right)
    if left.row == right.row then
      return left.col < right.col
    end
    return left.row < right.row
  end)

  return candidates[1] and candidates[1].path or nil
end

local function toggle_breakpoint_at(path, line)
  local target = normalize(path)
  if not target or not vim.uv.fs_stat(target) then
    append_console({ 'No source file available for breakpoint command.' })
    return
  end

  local previous_win = vim.api.nvim_get_current_win()
  local previous_buf = vim.api.nvim_get_current_buf()
  local previous_cursor = vim.api.nvim_win_get_cursor(previous_win)
  local bufnr = vim.fn.bufnr(target, true)
  vim.fn.bufload(bufnr)
  vim.api.nvim_win_set_buf(previous_win, bufnr)
  vim.api.nvim_win_set_cursor(previous_win, { math.max(1, line), 0 })
  require('dap').toggle_breakpoint()
  if vim.api.nvim_win_is_valid(previous_win) then
    vim.api.nvim_win_set_buf(previous_win, previous_buf)
    pcall(vim.api.nvim_win_set_cursor, previous_win, previous_cursor)
  end
end

local function evaluate_expression(expression, callback)
  if not expression or expression == '' then
    callback(nil, nil)
    return
  end
  if not state.current_frame_id then
    callback('No stopped stack frame to evaluate against.')
    return
  end

  session_request('evaluate', {
    expression = expression,
    frameId = state.current_frame_id,
    context = 'watch',
  }, function(err, response)
    if err then
      callback(err)
      return
    end
    callback(nil, response and response.result or nil)
  end)
end

local function refresh_locals_and_displays(announce_displays)
  if not state.current_frame_id then
    set_panel_lines(state.panels.locals, { 'No locals yet.' })
    return
  end

  session_request('scopes', {
    frameId = state.current_frame_id,
  }, function(err, response)
    if err or not response or not response.scopes then
      set_panel_lines(state.panels.locals, { 'Failed to load locals.' })
      return
    end

    local target_scope
    for _, scope in ipairs(response.scopes) do
      local name = (scope.name or ''):lower()
      if name:find('local', 1, true) or name:find('arg', 1, true) then
        target_scope = scope
        break
      end
    end
    target_scope = target_scope or response.scopes[1]

    local function render(local_lines)
      local lines = { 'Locals:' }
      vim.list_extend(lines, local_lines)
      if #state.display_expressions > 0 then
        table.insert(lines, '')
        table.insert(lines, 'Display:')
        for index, expr in ipairs(state.display_expressions) do
          local value = state.display_values[expr]
          if value and value ~= '' then
            table.insert(lines, string.format('  [%d] %s = %s', index, expr, value))
          else
            table.insert(lines, string.format('  [%d] %s', index, expr))
          end
        end
      end
      set_panel_lines(state.panels.locals, lines)
      if announce_displays and not state.panels.locals.shown then
        local display_lines = {}
        for _, expr in ipairs(state.display_expressions) do
          local value = state.display_values[expr]
          if value and value ~= '' then
            table.insert(display_lines, string.format('[display] %s = %s', expr, value))
          end
        end
        if #display_lines > 0 and state.panels.command.bufnr then
          append_console(display_lines)
        end
      end
    end

    local function refresh_displays(local_lines)
      if #state.display_expressions == 0 then
        render(local_lines)
        return
      end

      local pending = #state.display_expressions
      local values = {}
      for _, expr in ipairs(state.display_expressions) do
        evaluate_expression(expr, function(eval_err, result)
          if not eval_err and result and result ~= '' then
            values[expr] = result
          end
          pending = pending - 1
          if pending == 0 then
            state.display_values = values
            render(local_lines)
          end
        end)
      end
    end

    session_request('variables', {
      variablesReference = target_scope.variablesReference,
    }, function(var_err, vars_response)
      local local_lines = {}
      if var_err or not vars_response or not vars_response.variables then
        table.insert(local_lines, '  <failed to load variables>')
      else
        for _, variable in ipairs(vars_response.variables) do
          table.insert(local_lines, string.format('  %s = %s', variable.name or '?', variable.value or ''))
        end
      end
      refresh_displays(local_lines)
    end)
  end)
end

local function request_step(command)
  if not state.current_thread_id then
    return false
  end
  session_request(command, {
    threadId = state.current_thread_id,
  }, function(err)
    if err then
      state.pending_project_step = nil
      append_console({ 'Step failed: ' .. tostring(err) })
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

local function project_step(command)
  if request_step(command) then
    state.pending_project_step = {
      command = command,
      remaining = 50,
    }
    return
  end
  raw_step(command)
end

local function resolve_command(name)
  local commands = {
    continue = { 'c', 'cont', 'continue' },
    next = { 'n', 'next' },
    step = { 's', 'step' },
    stepr = { 'S' },
    out = { 'u', 'finish', 'out' },
    outr = { 'U' },
    breakp = { 'b', 'break' },
    display = { 'display', 'disp' },
    undisplay = { 'undisplay', 'undisp' },
    locals = { 'locals', 'info locals' },
    help = { '?', 'h', 'help' },
    print = { 'p', 'print' },
  }

  for canonical, aliases in pairs(commands) do
    for _, alias in ipairs(aliases) do
      if name == alias then
        return canonical
      end
      if alias:match('^[a-z]') and alias:find(name, 1, true) == 1 then
        return canonical
      end
    end
  end
end

local function help_lines()
  return {
    'Commands:',
    '  ? / help            Show this help',
    '  c / continue        Continue execution',
    '  n / next            Step over',
    '  s / step            Step into, skipping non-project code',
    '  S                   Step into without skipping',
    '  u / out             Step out, skipping non-project code',
    '  U                   Step out without skipping',
    '  b [line]            Toggle breakpoint on current/preferred file',
    '  > expr              Evaluate expression',
    '  p expr              Evaluate expression',
    '  display expr        Add watched display expression',
    '  undisplay [n]       Remove one display or clear all',
    '  locals              Refresh local variables',
    '  <Enter>             Repeat previous command',
  }
end

local function execute_console_command(line)
  local command_line = vim.trim(line or '')
  if command_line == '' then
    command_line = state.last_command or ''
  else
    state.last_command = command_line
  end

  if command_line == '' then
    return
  end

  if command_line:sub(1, 1) == '>' then
    local expression = vim.trim(command_line:sub(2))
    evaluate_expression(expression, function(err, result)
      if err then
        append_console({ tostring(err) })
        return
      end
      append_console({ string.format('%s = %s', expression, result or '<nil>') })
    end)
    return
  end

  local name, rest = command_line:match('^(%S+)%s*(.*)$')
  local command = resolve_command(name or '')
  if not command then
    append_console({ 'Unknown command: ' .. command_line })
    return
  end

  if command == 'help' then
    append_console(help_lines())
    return
  end

  if command == 'continue' then
    require('dap').continue()
    return
  end

  if command == 'next' then
    raw_step('next')
    return
  end

  if command == 'step' then
    project_step('stepIn')
    return
  end

  if command == 'stepr' then
    raw_step('stepIn')
    return
  end

  if command == 'out' then
    project_step('stepOut')
    return
  end

  if command == 'outr' then
    raw_step('stepOut')
    return
  end

  if command == 'print' then
    local expression = vim.trim(rest or '')
    evaluate_expression(expression, function(err, result)
      if err then
        append_console({ tostring(err) })
        return
      end
      append_console({ string.format('%s = %s', expression, result or '<nil>') })
    end)
    return
  end

  if command == 'display' then
    local expression = vim.trim(rest or '')
    if expression == '' then
      if #state.display_expressions == 0 then
        append_console({ 'No display expressions.' })
      else
        local lines = {}
        for index, expr in ipairs(state.display_expressions) do
          table.insert(lines, string.format('[%d] %s', index, expr))
        end
        append_console(lines)
      end
      return
    end
    table.insert(state.display_expressions, expression)
    refresh_locals_and_displays(false)
    append_console({ 'display ' .. expression })
    return
  end

  if command == 'undisplay' then
    local arg = vim.trim(rest or '')
    if arg == '' then
      state.display_expressions = {}
      state.display_values = {}
    else
      local index = tonumber(arg)
      if index and state.display_expressions[index] then
        local expr = state.display_expressions[index]
        table.remove(state.display_expressions, index)
        state.display_values[expr] = nil
      end
    end
    refresh_locals_and_displays(false)
    append_console({ 'display list updated' })
    return
  end

  if command == 'locals' then
    refresh_locals_and_displays(false)
    return
  end

  if command == 'breakp' then
    local target = target_file_for_breakpoint()
    if not target then
      append_console({ 'No source file available for breakpoint command.' })
      return
    end
    local line_number = tonumber(vim.trim(rest or ''))
    if not line_number then
      local current_buf = vim.api.nvim_get_current_buf()
      if is_panel_buf(current_buf) then
        local win = vim.fn.bufwinid(vim.fn.bufnr(target))
        if win ~= -1 then
          line_number = vim.api.nvim_win_get_cursor(win)[1]
        else
          line_number = 1
        end
      else
        line_number = vim.api.nvim_win_get_cursor(0)[1]
        target = normalize(vim.api.nvim_buf_get_name(current_buf)) or target
      end
    end
    toggle_breakpoint_at(target, line_number)
    append_console({ string.format('breakpoint toggled at %s:%d', vim.fn.fnamemodify(target, ':.'), line_number) })
  end
end

local function configure_command_prompt(bufnr)
  vim.fn.prompt_setcallback(bufnr, function(line)
    execute_console_command(line)
    vim.schedule(function()
      if state.panels.command.winid and vim.api.nvim_win_is_valid(state.panels.command.winid) then
        vim.api.nvim_set_current_win(state.panels.command.winid)
        vim.cmd('startinsert')
      end
    end)
  end)
end

local function create_command_buffer()
  local panel = state.panels.command
  local bufnr = create_panel_buffer(panel)
  configure_command_prompt(bufnr)
  return bufnr
end

local function append_output(body)
  local category = body.category or 'output'
  local text = body.output or ''
  if text == '' then
    return
  end

  local prefix = '[' .. category .. '] '
  local lines = {}
  local first = true
  for chunk in text:gmatch('([^\n]*)\n?') do
    if chunk == '' and first == false then
      break
    end
    table.insert(lines, prefix .. chunk)
    first = false
  end
  append_panel_lines(state.panels.output, lines)
end

function M.toggle_output()
  if #state.panels.output.lines == 0 then
    vim.notify('No DAP output available.', vim.log.levels.INFO)
    return
  end
  toggle_panel('output')
end

function M.toggle_command()
  if state.panels.command.shown then
    hide_panel('command')
    return
  end
  create_command_buffer()
  show_panel('command')
  if state.panels.command.winid and vim.api.nvim_win_is_valid(state.panels.command.winid) then
    vim.api.nvim_set_current_win(state.panels.command.winid)
    vim.cmd('startinsert')
  end
end

function M.toggle_locals()
  toggle_panel('locals')
end

function M.set_project_root(root)
  state.project_root = normalize(root)
end

function M.execute_command(line)
  execute_console_command(line)
end

function M.handle_stopped(_, body)
  state.current_thread_id = body and body.threadId or state.current_thread_id
  if not state.current_thread_id then
    return
  end

  session_request('stackTrace', {
    threadId = state.current_thread_id,
    startFrame = 0,
    levels = 1,
  }, function(err, response)
    if err or not response or not response.stackFrames or not response.stackFrames[1] then
      state.pending_project_step = nil
      return
    end

    local frame = response.stackFrames[1]
    state.current_frame_id = frame.id
    local source_path = frame.source and normalize(frame.source.path) or nil
    local outside_project = false

    if source_path and state.project_root then
      outside_project = not starts_with_path(source_path, state.project_root)
      if not outside_project and vim.uv.fs_stat(source_path) then
        local line_count = #vim.fn.readfile(source_path)
        if frame.line and line_count > 0 and frame.line > line_count then
          outside_project = true
        end
      end
    end

    local pending = state.pending_project_step
    if pending and outside_project and pending.remaining > 0 then
      pending.remaining = pending.remaining - 1
      request_step(pending.command)
      return
    end

    state.pending_project_step = nil
    refresh_locals_and_displays(true)
  end)
end

function M.ensure_listeners()
  if state.listeners_attached then
    return true
  end

  local ok, dap = pcall(require, 'dap')
  if not ok then
    return false
  end

  dap.listeners = dap.listeners or {}
  dap.listeners.after = dap.listeners.after or {}
  dap.listeners.before = dap.listeners.before or {}
  dap.listeners.after.event_output = dap.listeners.after.event_output or {}
  dap.listeners.after.event_stopped = dap.listeners.after.event_stopped or {}
  dap.listeners.before.event_continued = dap.listeners.before.event_continued or {}
  dap.listeners.before.event_exited = dap.listeners.before.event_exited or {}
  dap.listeners.before.event_terminated = dap.listeners.before.event_terminated or {}

  dap.listeners.after.event_output.user_dap_panels = function(_, body)
    vim.schedule(function()
      append_output(body)
    end)
  end
  dap.listeners.after.event_stopped.user_dap_panels = function(session, body)
    vim.schedule(function()
      M.handle_stopped(session, body)
    end)
  end
  dap.listeners.before.event_continued.user_dap_panels = function()
    state.pending_project_step = nil
  end
  dap.listeners.before.event_exited.user_dap_panels = function()
    state.current_thread_id = nil
    state.current_frame_id = nil
    state.pending_project_step = nil
  end
  dap.listeners.before.event_terminated.user_dap_panels = function()
    state.current_thread_id = nil
    state.current_frame_id = nil
    state.pending_project_step = nil
  end
  state.listeners_attached = true

  vim.api.nvim_create_autocmd('BufEnter', {
    group = vim.api.nvim_create_augroup('UserDapPanelTracking', { clear = true }),
    callback = function(args)
      if is_panel_buf(args.buf) or vim.bo[args.buf].buftype ~= '' then
        return
      end
      local name = normalize(vim.api.nvim_buf_get_name(args.buf))
      if name and name ~= '' then
        state.last_visited_file = name
      end
    end,
  })

  vim.api.nvim_create_autocmd('VimResized', {
    group = vim.api.nvim_create_augroup('UserDapPanelResize', { clear = true }),
    callback = layout_panels,
  })

  return true
end

M._state = state

return M
