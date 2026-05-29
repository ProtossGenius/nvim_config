local M = {}

local OUTPUT_PANEL_HEIGHT = 8
local LOCALS_PANEL_HEIGHT = 10
local POPUP_PROMPT = ''
local PANEL_ORDER = { 'locals', 'output' }
local LOG_PATH = vim.fs.normalize(vim.fn.stdpath('state') .. '/user-dap.log')

local state = {
  listeners_attached = false,
  panels = {
    output = { key = 'output', title = 'DAP Output', shown = false, lines = {} },
    locals = { key = 'locals', title = 'DAP Locals', shown = false, lines = { 'No locals yet.' } },
  },
  visible_order = {},
  display_expressions = {},
  display_values = {},
  project_root = nil,
  current_thread_id = nil,
  current_frame_id = nil,
  current_source_path = nil,
  current_frame_line = nil,
  current_outside_project = false,
  current_unsafe_source = false,
  pending_project_step = nil,
  last_visited_file = nil,
  source_winid = nil,
  last_action = nil,
  session_stopped = false,
  popup = nil,
}

local function normalize(path)
  if not path or path == '' then
    return nil
  end
  return vim.fs.normalize(path)
end

local function format_log_context(context)
  if not context then
    return ''
  end
  local ok, rendered = pcall(vim.inspect, context)
  if not ok or not rendered or rendered == '' then
    return ''
  end
  rendered = rendered:gsub('%s+', ' '):gsub('^%s+', '')
  return ' ' .. rendered
end

local function append_log(level, message, context)
  local line = string.format(
    '%s [%s] %s%s',
    os.date('%Y-%m-%d %H:%M:%S'),
    level,
    message,
    format_log_context(context)
  )
  pcall(vim.fn.writefile, { line }, LOG_PATH, 'a')
end

local function log_info(message, context)
  append_log('INFO', message, context)
end

local function log_warn(message, context)
  append_log('WARN', message, context)
end

local function clear_stop_state()
  state.session_stopped = false
  state.current_thread_id = nil
  state.current_frame_id = nil
  state.current_source_path = nil
  state.current_frame_line = nil
  state.current_outside_project = false
  state.current_unsafe_source = false
end

local function starts_with_path(path, root)
  return path == root or path:sub(1, #root + 1) == root .. '/'
end

local function is_project_managed_source(path)
  local normalized = normalize(path)
  if not normalized or not state.project_root or normalized:match('^%a[%w+.-]*://') then
    return false
  end
  if not starts_with_path(normalized, state.project_root) then
    return false
  end
  for _, marker in ipairs({ '/target/', '/build/', '/out/', '/.gradle/', '/generated/' }) do
    if normalized:find(marker, 1, true) then
      return false
    end
  end
  return true
end

local function is_uri_like_source(path)
  return type(path) == 'string' and path:match('^%a[%w+.-]*://') ~= nil
end

local function describe_source(path, line)
  if path and path ~= '' then
    if line then
      return string.format('%s:%s', path, line)
    end
    return path
  end
  if line then
    return string.format('<unknown>:%s', line)
  end
  return '<unknown>'
end

local function analyze_frame_source(frame)
  local source_path = frame.source and normalize(frame.source.path) or nil
  local outside_project = false
  local unsafe_source = false

  if source_path then
    outside_project = not is_project_managed_source(source_path)
    if not outside_project and vim.uv.fs_stat(source_path) then
      local line_count = #vim.fn.readfile(source_path)
      if frame.line and line_count > 0 and frame.line > line_count then
        outside_project = true
        unsafe_source = true
      end
    elseif outside_project and (is_uri_like_source(source_path) or not vim.uv.fs_stat(source_path)) then
      unsafe_source = true
    end
  else
    outside_project = true
    unsafe_source = true
  end

  return source_path, outside_project, unsafe_source
end

local function set_stop_context(source_path, line, outside_project, unsafe_source)
  state.current_source_path = source_path
  state.current_frame_line = line
  state.current_outside_project = outside_project
  state.current_unsafe_source = unsafe_source
end

local function effective_step_command(command, opts)
  opts = opts or {}
  if command == 'stepOut' or command == 'next' then
    return command
  end

  if opts.project_managed then
    if state.current_outside_project then
      log_warn('Switching project step to stepOut outside project code.', {
        from = command,
        source = state.current_source_path,
        line = state.current_frame_line,
        unsafe = state.current_unsafe_source,
      })
      return 'stepOut'
    end
    return command
  end

  if state.current_unsafe_source then
    log_warn('Switching DAP step to stepOut for unsafe source frame.', {
      from = command,
      source = state.current_source_path,
      line = state.current_frame_line,
    })
    return 'stepOut'
  end

  return command
end

local function notify_step_termination(kind)
  local action = state.pending_project_step and state.pending_project_step.command or state.last_action
  if not action then
    return
  end
  if not state.pending_project_step and not state.current_unsafe_source then
    return
  end
  vim.notify(
    string.format(
      'DAP session %s while handling %s near %s.',
      kind,
      action,
      describe_source(state.current_source_path, state.current_frame_line)
    ),
    vim.log.levels.WARN
  )
end

local function current_session()
  local ok, dap = pcall(require, 'dap')
  if not ok or not dap.session then
    return nil
  end
  return dap.session()
end

local function is_panel_buf(bufnr)
  for _, panel in pairs(state.panels) do
    if panel.bufnr == bufnr then
      return true
    end
  end
  if state.popup and state.popup.bufnr == bufnr then
    return true
  end
  return false
end

local function sync_visible_order()
  state.visible_order = {}
  for _, key in ipairs(PANEL_ORDER) do
    if state.panels[key].shown then
      table.insert(state.visible_order, key)
    end
  end
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

local function create_panel_buffer(panel)
  if panel.bufnr and vim.api.nvim_buf_is_valid(panel.bufnr) then
    return panel.bufnr
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  panel.bufnr = bufnr
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].bufhidden = 'hide'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].buflisted = false
  vim.bo[bufnr].filetype = 'user-dap-' .. panel.key
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, panel.lines or {})
  vim.bo[bufnr].modifiable = false
  return bufnr
end

local function close_panel_window(panel)
  if panel.winid and vim.api.nvim_win_is_valid(panel.winid) then
    vim.api.nvim_win_close(panel.winid, true)
  end
  panel.winid = nil
end

local function preferred_source_window()
  if state.source_winid and vim.api.nvim_win_is_valid(state.source_winid) then
    local bufnr = vim.api.nvim_win_get_buf(state.source_winid)
    if not is_panel_buf(bufnr) and vim.bo[bufnr].buftype == '' then
      return state.source_winid
    end
  end

  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(winid) then
      local cfg = vim.api.nvim_win_get_config(winid)
      if cfg.relative == '' then
        local bufnr = vim.api.nvim_win_get_buf(winid)
        if not is_panel_buf(bufnr) and vim.bo[bufnr].buftype == '' then
          return winid
        end
      end
    end
  end
end

local function focus_source_window()
  local winid = preferred_source_window()
  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_set_current_win(winid)
    return winid
  end
end

local function configure_panel_window(panel)
  if not panel.winid or not vim.api.nvim_win_is_valid(panel.winid) then
    return
  end
  vim.wo[panel.winid].number = false
  vim.wo[panel.winid].relativenumber = false
  vim.wo[panel.winid].signcolumn = 'no'
  vim.wo[panel.winid].wrap = false
  vim.wo[panel.winid].winfixheight = true
  vim.api.nvim_win_set_option(panel.winid, 'winbar', ' ' .. panel.title)
end

local function layout_panels(focus_key)
  sync_visible_order()

  local locals_panel = state.panels.locals
  local output_panel = state.panels.output
  local restore_win = vim.api.nvim_get_current_win()
  if restore_win and vim.api.nvim_win_is_valid(restore_win) then
    local restore_buf = vim.api.nvim_win_get_buf(restore_win)
    if is_panel_buf(restore_buf) or vim.bo[restore_buf].buftype ~= '' then
      restore_win = preferred_source_window()
    end
  else
    restore_win = preferred_source_window()
  end

  close_panel_window(locals_panel)
  close_panel_window(output_panel)

  if not locals_panel.shown and not output_panel.shown then
    if restore_win and vim.api.nvim_win_is_valid(restore_win) then
      vim.api.nvim_set_current_win(restore_win)
    end
    return
  end

  local anchor_win = restore_win
  if not anchor_win or not vim.api.nvim_win_is_valid(anchor_win) then
    return
  end

  local focus_win = anchor_win

  if output_panel.shown then
    vim.api.nvim_set_current_win(anchor_win)
    vim.cmd(('botright %dsplit'):format(OUTPUT_PANEL_HEIGHT))
    output_panel.winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(output_panel.winid, create_panel_buffer(output_panel))
    configure_panel_window(output_panel)
    focus_win = output_panel.winid
  end

  if locals_panel.shown then
    local base_win = output_panel.winid or anchor_win
    vim.api.nvim_set_current_win(base_win)
    if output_panel.shown then
      vim.cmd(('leftabove %dsplit'):format(LOCALS_PANEL_HEIGHT))
    else
      vim.cmd(('botright %dsplit'):format(LOCALS_PANEL_HEIGHT))
    end
    locals_panel.winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(locals_panel.winid, create_panel_buffer(locals_panel))
    configure_panel_window(locals_panel)
    focus_win = locals_panel.winid
  end

  if focus_key then
    local panel = state.panels[focus_key]
    if panel and panel.winid and vim.api.nvim_win_is_valid(panel.winid) then
      focus_win = panel.winid
    end
  end

  if focus_win and vim.api.nvim_win_is_valid(focus_win) then
    vim.api.nvim_set_current_win(focus_win)
  end
end

local function show_panel(key)
  local panel = state.panels[key]
  if not panel or panel.shown then
    return
  end
  panel.shown = true
  create_panel_buffer(panel)
  layout_panels(key)
end

local function hide_panel(key)
  local panel = state.panels[key]
  if not panel or not panel.shown then
    return
  end
  panel.shown = false
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

local function close_popup()
  if not state.popup then
    return
  end
  if state.popup.winid and vim.api.nvim_win_is_valid(state.popup.winid) then
    vim.api.nvim_win_close(state.popup.winid, true)
  end
  state.popup = nil
end

local function popup_size(lines, min_width)
  local width = min_width or 60
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line) + 4)
  end
  width = math.min(width, math.max(50, vim.o.columns - 6))
  local height = math.min(math.max(#lines, 4), math.max(6, vim.o.lines - 6))
  return width, height
end

local function popup_input_payload(line)
  if type(line) ~= 'string' then
    return ''
  end
  if POPUP_PROMPT ~= '' and line:sub(1, #POPUP_PROMPT) == POPUP_PROMPT then
    return line:sub(#POPUP_PROMPT + 1)
  end
  return line
end

local function ensure_popup_prompt_line()
  if not state.popup or not state.popup.bufnr or not vim.api.nvim_buf_is_valid(state.popup.bufnr) then
    return
  end
  if state.popup.kind ~= 'eval_prompt' and state.popup.kind ~= 'display_prompt' then
    return
  end
  local bufnr = state.popup.bufnr
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { state.popup.title, '', POPUP_PROMPT })
    return
  end
  local last_line = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1] or ''
  local desired = POPUP_PROMPT .. popup_input_payload(last_line)
  if last_line ~= desired then
    vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count, false, { desired })
  end
end

local function focus_popup_prompt()
  if not state.popup or not state.popup.winid or not vim.api.nvim_win_is_valid(state.popup.winid) then
    return
  end
  ensure_popup_prompt_line()
  local line_count = vim.api.nvim_buf_line_count(state.popup.bufnr)
  vim.api.nvim_set_current_win(state.popup.winid)
  vim.api.nvim_win_set_cursor(state.popup.winid, { line_count, #POPUP_PROMPT })
  vim.cmd('startinsert')
end

local function set_popup_lines(lines)
  if not state.popup or not state.popup.bufnr or not vim.api.nvim_buf_is_valid(state.popup.bufnr) then
    return
  end
  vim.bo[state.popup.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.popup.bufnr, 0, -1, false, lines)
end

local function create_popup_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].buflisted = false
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

local function open_popup(title, lines, opts)
  opts = opts or {}
  close_popup()
  local width, height = popup_size(lines, opts.min_width)
  local row = math.floor((vim.o.lines - height) / 2 - 1)
  local col = math.floor((vim.o.columns - width) / 2)
  local bufnr = create_popup_buffer(lines)
  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = 'editor',
    row = math.max(1, row),
    col = math.max(0, col),
    width = width,
    height = height,
    border = 'single',
    style = 'minimal',
    title = title,
    title_pos = 'center',
    zindex = 60,
  })
  vim.wo[winid].wrap = false
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = 'no'
  vim.wo[winid].cursorline = opts.cursorline or false
  state.popup = {
    kind = opts.kind or 'message',
    title = title,
    bufnr = bufnr,
    winid = winid,
    items = opts.items,
  }
  vim.keymap.set('n', 'q', close_popup, { buffer = bufnr, silent = true, desc = 'Close popup' })
  vim.keymap.set({ 'n', 'i' }, '<Esc>', close_popup, { buffer = bufnr, silent = true, desc = 'Close popup' })
  return bufnr, winid
end

local function render_prompt_popup(lines)
  if not state.popup or not state.popup.bufnr or not vim.api.nvim_buf_is_valid(state.popup.bufnr) then
    return
  end
  set_popup_lines(lines)
  ensure_popup_prompt_line()
  focus_popup_prompt()
end

local function jump_to_location(path_or_uri, line)
  local target = path_or_uri
  if not target or target == '' then
    vim.notify('No source location available for this stack frame.', vim.log.levels.WARN)
    return
  end
  if not target:match('^%a[%w+.-]*://') then
    target = vim.uri_from_fname(target)
  end
  pcall(vim.lsp.util.jump_to_location, {
    uri = target,
    range = {
      start = { math.max((line or 1) - 1, 0), 0 },
      ['end'] = { math.max((line or 1) - 1, 0), 0 },
    },
  }, 'utf-16', true)
end

local function session_request(command, arguments, callback)
  local session = current_session()
  if not session then
    callback('No active DAP session.')
    return
  end
  local ok, err = pcall(session.request, session, command, arguments, callback)
  if not ok then
    log_warn('DAP session request threw error.', {
      command = command,
      error = tostring(err),
    })
    pcall(callback, 'Request failed: ' .. tostring(err))
  end
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
      if name and name ~= '' and vim.bo[bufnr].buftype == '' and not is_panel_buf(bufnr) then
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
    vim.notify('No source file available for breakpoint command.', vim.log.levels.WARN)
    return
  end

  local previous_win = vim.api.nvim_get_current_win()
  local invoke_win = preferred_source_window() or previous_win
  local previous_buf = vim.api.nvim_win_get_buf(invoke_win)
  local previous_cursor = vim.api.nvim_win_get_cursor(invoke_win)
  local bufnr = vim.fn.bufnr(target, true)
  vim.fn.bufload(bufnr)
  vim.api.nvim_set_current_win(invoke_win)
  vim.api.nvim_win_set_buf(invoke_win, bufnr)
  vim.api.nvim_win_set_cursor(invoke_win, { math.max(1, line), 0 })
  require('dap').toggle_breakpoint()
  if vim.api.nvim_win_is_valid(invoke_win) then
    vim.api.nvim_win_set_buf(invoke_win, previous_buf)
    pcall(vim.api.nvim_win_set_cursor, invoke_win, previous_cursor)
  end
  if previous_win and vim.api.nvim_win_is_valid(previous_win) then
    vim.api.nvim_set_current_win(previous_win)
  end
end

local function pretty_json(value, indent)
  indent = indent or 0
  local prefix = string.rep('  ', indent)
  local child_prefix = string.rep('  ', indent + 1)

  if value == nil then
    return 'null'
  end
  if type(value) == 'string' then
    return vim.json.encode(value)
  end
  if type(value) == 'number' or type(value) == 'boolean' then
    return tostring(value)
  end
  if vim.islist(value) then
    if #value == 0 then
      return '[]'
    end
    local parts = { '[' }
    for index, item in ipairs(value) do
      local suffix = index < #value and ',' or ''
      table.insert(parts, child_prefix .. pretty_json(item, indent + 1) .. suffix)
    end
    table.insert(parts, prefix .. ']')
    return table.concat(parts, '\n')
  end

  local keys = vim.tbl_keys(value)
  table.sort(keys)
  if #keys == 0 then
    return '{}'
  end
  local parts = { '{' }
  for index, key in ipairs(keys) do
    local suffix = index < #keys and ',' or ''
    table.insert(parts, child_prefix .. vim.json.encode(key) .. ': ' .. pretty_json(value[key], indent + 1) .. suffix)
  end
  table.insert(parts, prefix .. '}')
  return table.concat(parts, '\n')
end

local function compact_json(value)
  local ok, encoded = pcall(vim.json.encode, value)
  if ok and encoded then
    return encoded
  end
  return tostring(value)
end

local function scalar_value(text)
  if text == nil then
    return nil
  end
  if text == 'true' then
    return true
  end
  if text == 'false' then
    return false
  end
  if text == 'null' then
    return nil
  end
  local number = tonumber(text)
  if number ~= nil then
    return number
  end
  return text
end

local function simple_type_name(type_name)
  if not type_name or type_name == '' then
    return nil
  end
  return type_name:match('([%w_$]+)$') or type_name
end

local SPRING_BEAN_PATTERNS = {
  'Controller$', 'Service$', 'ServiceImpl$', 'Repository$', 'Mapper$',
  'Configuration$', 'Component$', 'Interceptor$', 'Filter$', 'Advisor$',
  'Handler$', 'Resolver$', 'Factory$', 'Proxy$', 'CGLIB', '%$%$',
}

local function is_spring_bean(type_name)
  local simple = simple_type_name(type_name)
  if not simple then
    return false
  end
  for _, pattern in ipairs(SPRING_BEAN_PATTERNS) do
    if simple:match(pattern) then
      return true
    end
  end
  return false
end

local function format_basic_value(type_name, value_text)
  if not type_name or not value_text then
    return nil
  end
  local simple = simple_type_name(type_name)
  if not simple then
    return nil
  end
  local is_basic = false
  local lower_simple = simple:lower()
  if lower_simple == 'string' or lower_simple == 'long' or lower_simple == 'integer' or lower_simple == 'int'
     or lower_simple == 'short' or lower_simple == 'byte' or lower_simple == 'float' or lower_simple == 'double'
     or lower_simple == 'char' or lower_simple == 'character' or lower_simple == 'boolean' then
    is_basic = true
  end

  if not is_basic then
    return nil
  end

  if lower_simple == 'string' then
    local s = value_text
    if s:sub(1, 1) == '"' and s:sub(-1, -1) == '"' then
      return s
    end
    if s:sub(1, 1) == "'" and s:sub(-1, -1) == "'" then
      return '"' .. s:sub(2, -2) .. '"'
    end
    return '"' .. s .. '"'
  end

  if lower_simple == 'long' then
    local s = value_text
    if s:match('^%d+[Ll]$') then
      return s:sub(1, -2)
    end
    return s
  end

  return value_text
end

local function inspect_variable(variable, depth, callback, opts)
  depth = depth or 0
  opts = opts or {}
  local info = {
    type = variable and variable.type or nil,
    text = variable and variable.value or nil,
    value = scalar_value(variable and variable.value or nil),
  }

  local variables_reference = variable and variable.variablesReference or 0
  if opts.compact and variables_reference > 0 and is_spring_bean(info.type) and depth == 0 then
    local short = simple_type_name(info.type) or info.text or '...'
    info.value = short
    info.pretty = short
    info.inline = short
    info.is_complex = true
    callback(info)
    return
  end

  if variables_reference <= 0 or depth >= 3 then
    local basic_formatted = format_basic_value(info.type, info.text)
    if basic_formatted then
      info.pretty = basic_formatted
      info.inline = basic_formatted
    else
      info.pretty = pretty_json(info.value)
      info.inline = compact_json(info.value)
    end
    callback(info)
    return
  end

  session_request('variables', {
    variablesReference = variables_reference,
  }, function(err, response)
    if err or not response or not response.variables then
      info.pretty = pretty_json(info.value)
      info.inline = compact_json(info.value)
      callback(info)
      return
    end

    local children = response.variables
    if #children == 0 then
      info.value = {}
      info.pretty = pretty_json(info.value)
      info.inline = compact_json(info.value)
      callback(info)
      return
    end

    local pending = #children
    local only_array = true
    local array_values = {}
    local object_values = {}

    for _, child in ipairs(children) do
      inspect_variable(child, depth + 1, function(child_info)
        local index = child.name and child.name:match('^%[(%d+)%]$')
        if index then
          array_values[tonumber(index) + 1] = child_info.value
        else
          only_array = false
          object_values[child.name or '?'] = child_info.value
        end

        pending = pending - 1
        if pending == 0 then
          if only_array and next(array_values) ~= nil then
            info.value = array_values
          else
            if next(array_values) ~= nil then
              for idx, value in ipairs(array_values) do
                object_values[tostring(idx - 1)] = value
              end
            end
            info.value = object_values
          end
          info.pretty = pretty_json(info.value)
          info.inline = compact_json(info.value)
          callback(info)
        end
      end)
    end
  end)
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
    inspect_variable({
      type = response and response.type or nil,
      value = response and response.result or nil,
      variablesReference = response and response.variablesReference or 0,
    }, 0, function(info)
      callback(nil, info)
    end)
  end)
end

local function valid_display_items()
  local items = {}
  for _, expr in ipairs(state.display_expressions) do
    local info = state.display_values[expr]
    if info and info.inline and info.inline ~= '' then
      table.insert(items, { expr = expr, info = info })
    end
  end
  return items
end

local function render_display_picker()
  if not state.popup or state.popup.kind ~= 'display_list' or not state.popup.bufnr or not vim.api.nvim_buf_is_valid(state.popup.bufnr) then
    return
  end
  local items = valid_display_items()
  state.popup.items = items
  local lines = { 'Displays with values:', '' }
  for index, item in ipairs(items) do
    local suffix = item.info.type and item.info.type ~= '' and (' <' .. item.info.type .. '>') or ''
    table.insert(lines, string.format('[%d] %s%s %s', index, item.expr, suffix, item.info.inline))
  end
  if #items == 0 then
    close_popup()
    return
  end
  set_popup_lines(lines)
  vim.bo[state.popup.bufnr].modifiable = false
  local cursor_line = math.min(vim.api.nvim_win_get_cursor(state.popup.winid)[1], #lines)
  if cursor_line < 3 then
    cursor_line = 3
  end
  vim.api.nvim_win_set_cursor(state.popup.winid, { cursor_line, 0 })
end

local function extend_value_lines(lines, prefix, name, info)
  local label = prefix .. (name or '?')
  local short_type = simple_type_name(info.type)
  if short_type and short_type ~= '' then
    label = label .. ' <' .. short_type .. '>'
  end
  if info.is_complex then
    table.insert(lines, label)
    return
  end
  local display = info.inline or compact_json(info.value)
  table.insert(lines, label .. ' ' .. display)
end

local function refresh_locals_and_displays()
  if not state.current_frame_id then
    set_panel_lines(state.panels.locals, { 'No locals yet.' })
    render_display_picker()
    return
  end

  session_request('scopes', {
    frameId = state.current_frame_id,
  }, function(err, response)
    if err or not response or not response.scopes then
      set_panel_lines(state.panels.locals, { 'Failed to load locals.' })
      render_display_picker()
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
          local info = state.display_values[expr]
          if info and info.inline and info.inline ~= '' then
            extend_value_lines(lines, '  ', string.format('[%d] %s', index, expr), info)
          else
            table.insert(lines, string.format('  [%d] %s', index, expr))
          end
        end
      end
      set_panel_lines(state.panels.locals, lines)
      render_display_picker()
    end

    local function refresh_displays(local_lines)
      if #state.display_expressions == 0 then
        state.display_values = {}
        render(local_lines)
        return
      end

      local pending = #state.display_expressions
      local values = {}
      for _, expr in ipairs(state.display_expressions) do
        evaluate_expression(expr, function(eval_err, info)
          if not eval_err and info and info.inline and info.inline ~= '' then
            values[expr] = info
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
        local variables = vars_response.variables
        if #variables == 0 then
          table.insert(local_lines, '  <no locals>')
        else
          local pending_locals = #variables
          for _, variable in ipairs(variables) do
            inspect_variable(variable, 0, function(info)
              extend_value_lines(local_lines, '  ', variable.name or '?', info)
              pending_locals = pending_locals - 1
              if pending_locals == 0 then
                refresh_displays(local_lines)
              end
            end, { compact = true })
          end
          return
        end
      end
      refresh_displays(local_lines)
    end)
  end)
end

local function request_step(command)
  if not state.current_thread_id then
    log_warn('Cannot request step without stopped thread.', {
      command = command,
      session_stopped = state.session_stopped,
    })
    return false
  end
  log_info('Requesting DAP step.', {
    command = command,
    thread_id = state.current_thread_id,
    pending = state.pending_project_step and state.pending_project_step.command or nil,
  })
  session_request(command, {
    threadId = state.current_thread_id,
  }, function(err)
    if err then
      state.pending_project_step = nil
      log_warn('DAP step request failed.', {
        command = command,
        error = err,
      })
      vim.notify('Step failed: ' .. tostring(err), vim.log.levels.ERROR)
    end
  end)
  return true
end

local function raw_step(command, opts)
  local dap = require('dap')
  local effective_command = command
  opts = opts or {}
  if not opts.force_raw then
    effective_command = effective_step_command(command)
  end
  state.pending_project_step = nil
  state.session_stopped = false
  log_info('Running raw DAP step.', {
    command = effective_command,
    requested = command,
    last_action = state.last_action,
  })
  if effective_command == 'next' then
    dap.step_over()
  elseif effective_command == 'stepOut' then
    dap.step_out()
  else
    dap.step_into()
  end
end

local function project_step(command)
  if request_step(command) then
    state.session_stopped = false
    state.pending_project_step = {
      command = command,
      remaining = 200,
    }
    log_info('Starting project-managed DAP step.', {
      command = command,
      remaining = state.pending_project_step.remaining,
    })
    return true
  end
  raw_step(command)
  return true
end

local function stack_items(project_only)
  local popup = state.popup
  local frames = popup and popup.frames or {}
  local items = {}
  for _, frame in ipairs(frames) do
    local source = frame.source or {}
    local source_path = normalize(source.path) or source.path or source.name
    local in_project = is_project_managed_source(source_path)
    if not project_only or in_project then
      local short_source = source_path and not tostring(source_path):match('^%a[%w+.-]*://') and vim.fn.fnamemodify(source_path, ':.') or (source_path or '<unknown>')
      table.insert(items, {
        frame = frame,
        label = string.format('%s -> %s:%s', frame.name or '<frame>', short_source, tostring(frame.line or '?')),
      })
    end
  end
  return items
end

local function render_stack_popup()
  if not state.popup or state.popup.kind ~= 'stack_list' or not state.popup.winid or not vim.api.nvim_win_is_valid(state.popup.winid) then
    return
  end
  local items = stack_items(state.popup.project_only)
  state.popup.items = items
  local title = state.popup.project_only and 'DAP Stack [project]' or 'DAP Stack [all]'
  local lines = { title, '' }
  if #items == 0 then
    table.insert(lines, '<no stack frames>')
  else
    for index, item in ipairs(items) do
      table.insert(lines, string.format('[%d] %s', index, item.label))
    end
  end
  table.insert(lines, '')
  table.insert(lines, 'f=filter  Enter=jump  q=close')
  set_popup_lines(lines)
  vim.bo[state.popup.bufnr].modifiable = false
  if #items > 0 then
    local cursor_line = math.min(math.max(vim.api.nvim_win_get_cursor(state.popup.winid)[1], 3), #lines - 2)
    vim.api.nvim_win_set_cursor(state.popup.winid, { cursor_line, 0 })
  end
end

local function remember_action(name)
  state.last_action = name
  log_info('Remembered DAP action.', { action = name })
end

local function run_named_action(name, remember, opts)
  opts = opts or {}
  pcall(function()
    require('user.audit').log_dap_action(name, {
      remember = remember,
      opts = opts,
      state = {
        session_stopped = state.session_stopped,
        current_thread_id = state.current_thread_id,
        current_frame_id = state.current_frame_id,
        last_action = state.last_action,
        pending_project_step = state.pending_project_step and {
          command = state.pending_project_step.command,
          remaining = state.pending_project_step.remaining
        } or nil,
      }
    })
  end)
  if name == 'continue' or name == 'next' or name == 'step_project' or name == 'step_raw' or name == 'out_project' or name == 'out_raw' then
    if not current_session() then
      log_warn('Blocked DAP action without active session.', { action = name })
      vim.notify('No active DAP session.', vim.log.levels.INFO)
      return false
    end
    if not state.session_stopped then
      log_info('Blocked DAP action while session is running.', {
        action = name,
        repeat_action = opts.repeat_action or false,
      })
      if not opts.silent_when_running then
        vim.notify('DAP session is running. Wait for it to stop before stepping again.', vim.log.levels.INFO)
      end
      return false
    end
  end

  if remember ~= false then
    remember_action(name)
  end

  if name == 'continue' then
    state.pending_project_step = nil
    state.session_stopped = false
    log_info('Running DAP continue.', {})
    require('dap').continue()
    return true
  end
  if name == 'next' then
    raw_step('next')
    return true
  end
  if name == 'step_project' then
    return project_step('stepIn')
  end
  if name == 'step_raw' then
    raw_step('stepIn', { force_raw = true })
    return true
  end
  if name == 'out_project' then
    return project_step('stepOut')
  end
  if name == 'out_raw' then
    raw_step('stepOut', { force_raw = true })
    return true
  end
  return false
end

local function open_prompt_popup(kind, title)
  local lines = { title, '', POPUP_PROMPT }
  local bufnr, winid = open_popup(title, lines, {
    kind = kind,
    min_width = 70,
  })
  vim.keymap.set({ 'n', 'i' }, '<CR>', function()
    require('user.dap_ui').submit_popup()
  end, { buffer = bufnr, silent = true, desc = 'Submit popup command' })
  vim.keymap.set({ 'n', 'i' }, '<C-u>', function()
    require('user.dap_ui').clear_popup_input()
  end, { buffer = bufnr, silent = true, desc = 'Clear popup input' })
  state.popup.kind = kind
  state.popup.title = title
  vim.bo[bufnr].modifiable = true
  ensure_popup_prompt_line()
  vim.api.nvim_set_current_win(winid)
  vim.api.nvim_win_set_cursor(winid, { vim.api.nvim_buf_line_count(bufnr), 0 })
  vim.cmd('startinsert')
end

local function render_popup_result(title, expression, info, err)
  local lines = { title, '' }
  if err then
    table.insert(lines, tostring(err))
  else
    table.insert(lines, 'Expression: ' .. expression)
    if info.type and info.type ~= '' then
      table.insert(lines, 'Type: ' .. info.type)
    end
    table.insert(lines, 'Value:')
    for _, line in ipairs(vim.split(info.pretty or pretty_json(info.value), '\n', { plain = true })) do
      table.insert(lines, '  ' .. line)
    end
  end
  table.insert(lines, '')
  table.insert(lines, POPUP_PROMPT)
  render_prompt_popup(lines)
end

function M.toggle_output()
  if #state.panels.output.lines == 0 then
    vim.notify('No DAP output available.', vim.log.levels.INFO)
    return
  end
  toggle_panel('output')
end

function M.toggle_locals()
  toggle_panel('locals')
end

function M.set_project_root(root)
  state.project_root = normalize(root)
end

function M.run_action(name, remember)
  M.ensure_listeners()
  return run_named_action(name, remember)
end

function M.repeat_last_action()
  if not current_session() or not state.last_action then
    return false
  end
  if not state.session_stopped then
    log_info('Ignored DAP repeat while session is running.', {
      action = state.last_action,
    })
    return true
  end
  return run_named_action(state.last_action, false, {
    repeat_action = true,
    silent_when_running = true,
  })
end

function M.open_eval_popup()
  open_prompt_popup('eval_prompt', 'DAP Eval')
end

function M.open_display_add_popup()
  open_prompt_popup('display_prompt', 'DAP Display Add')
end

function M.open_display_list()
  local items = valid_display_items()
  if #items == 0 then
    vim.notify('No display values available.', vim.log.levels.INFO)
    return
  end
  local lines = { 'Displays with values:', '' }
  for index, item in ipairs(items) do
    table.insert(lines, string.format('[%d] %s = %s', index, item.expr, item.value))
  end
  local bufnr = open_popup('DAP Displays', lines, {
    kind = 'display_list',
    items = items,
    min_width = 72,
    cursorline = true,
  })
  vim.bo[bufnr].modifiable = false
  vim.keymap.set('n', 'd', function()
    require('user.dap_ui').delete_selected_display()
  end, { buffer = bufnr, silent = true, desc = 'Delete display' })
  vim.keymap.set('n', 'D', function()
    require('user.dap_ui').delete_selected_display()
  end, { buffer = bufnr, silent = true, desc = 'Delete display' })
  if state.popup and state.popup.winid and vim.api.nvim_win_is_valid(state.popup.winid) then
    vim.api.nvim_win_set_cursor(state.popup.winid, { 3, 0 })
  end
end

function M.open_stack_popup()
  if not state.current_thread_id then
    vim.notify('No stopped thread available for stack view.', vim.log.levels.INFO)
    return
  end
  session_request('stackTrace', {
    threadId = state.current_thread_id,
    startFrame = 0,
    levels = 100,
  }, function(err, response)
    if err or not response or not response.stackFrames then
      vim.notify('Failed to load stack frames.', vim.log.levels.WARN)
      return
    end
    local bufnr = open_popup('DAP Stack', { 'DAP Stack', '' }, {
      kind = 'stack_list',
      min_width = 90,
      cursorline = true,
    })
    state.popup.frames = response.stackFrames
    state.popup.project_only = false
    render_stack_popup()
    vim.keymap.set('n', 'f', function()
      require('user.dap_ui').toggle_stack_filter()
    end, { buffer = bufnr, silent = true, desc = 'Toggle project-only stack filter' })
    vim.keymap.set('n', '<CR>', function()
      require('user.dap_ui').jump_selected_stack_frame()
    end, { buffer = bufnr, silent = true, desc = 'Jump to stack frame' })
  end)
end

function M.toggle_stack_filter()
  if not state.popup or state.popup.kind ~= 'stack_list' then
    return
  end
  state.popup.project_only = not state.popup.project_only
  render_stack_popup()
end

function M.jump_selected_stack_frame()
  if not state.popup or state.popup.kind ~= 'stack_list' or not state.popup.winid or not vim.api.nvim_win_is_valid(state.popup.winid) then
    return
  end
  local index = vim.api.nvim_win_get_cursor(state.popup.winid)[1] - 2
  local item = state.popup.items and state.popup.items[index] or nil
  if not item then
    return
  end
  close_popup()
  state.current_frame_id = item.frame.id
  local source = item.frame.source or {}
  local winid = preferred_source_window()
  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_set_current_win(winid)
  end
  jump_to_location(source.path or source.name, item.frame.line or 1)
  refresh_locals_and_displays()
end

function M.delete_selected_display()
  if not state.popup or state.popup.kind ~= 'display_list' or not state.popup.winid or not vim.api.nvim_win_is_valid(state.popup.winid) then
    return
  end
  local cursor_line = vim.api.nvim_win_get_cursor(state.popup.winid)[1]
  local index = cursor_line - 2
  local items = state.popup.items or {}
  local item = items[index]
  if not item then
    return
  end
  for display_index, expr in ipairs(state.display_expressions) do
    if expr == item.expr then
      table.remove(state.display_expressions, display_index)
      state.display_values[item.expr] = nil
      break
    end
  end
  refresh_locals_and_displays()
  render_display_picker()
end

function M.clear_popup_input()
  if not state.popup or not state.popup.bufnr or not vim.api.nvim_buf_is_valid(state.popup.bufnr) then
    return
  end
  if state.popup.kind ~= 'eval_prompt' and state.popup.kind ~= 'display_prompt' then
    return
  end
  vim.bo[state.popup.bufnr].modifiable = true
  local line_count = vim.api.nvim_buf_line_count(state.popup.bufnr)
  vim.api.nvim_buf_set_lines(state.popup.bufnr, line_count - 1, line_count, false, { POPUP_PROMPT })
  focus_popup_prompt()
end

function M.submit_popup()
  if not state.popup or not state.popup.bufnr or not vim.api.nvim_buf_is_valid(state.popup.bufnr) then
    return
  end
  if state.popup.kind ~= 'eval_prompt' and state.popup.kind ~= 'display_prompt' then
    return
  end
  local line_count = vim.api.nvim_buf_line_count(state.popup.bufnr)
  local line = vim.api.nvim_buf_get_lines(state.popup.bufnr, line_count - 1, line_count, false)[1] or ''
  local expression = vim.trim(popup_input_payload(line))
  if expression == '' then
    return
  end
  evaluate_expression(expression, function(err, info)
    if not err and state.popup and state.popup.kind == 'display_prompt' then
      local already_present = false
      for _, expr in ipairs(state.display_expressions) do
        if expr == expression then
          already_present = true
          break
        end
      end
      if not already_present then
        table.insert(state.display_expressions, expression)
      end
      if info and info.inline and info.inline ~= '' then
        state.display_values[expression] = info
      end
      refresh_locals_and_displays()
    end
    render_popup_result(state.popup and state.popup.title or 'DAP', expression, info, err)
  end)
end

function M.toggle_breakpoint_here()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_path = normalize(vim.api.nvim_buf_get_name(current_buf))
  local line = vim.api.nvim_win_get_cursor(0)[1]
  if not current_path or current_path == '' or vim.bo[current_buf].buftype ~= '' then
    local target = target_file_for_breakpoint()
    if not target then
      vim.notify('No source file available for breakpoint command.', vim.log.levels.WARN)
      return
    end
    local winid = vim.fn.bufwinid(vim.fn.bufnr(target))
    line = winid ~= -1 and vim.api.nvim_win_get_cursor(winid)[1] or 1
    toggle_breakpoint_at(target, line)
    return
  end
  toggle_breakpoint_at(current_path, line)
end

function M.handle_stopped(_, body)
  state.current_thread_id = body and body.threadId or state.current_thread_id
  state.session_stopped = true
  if not state.current_thread_id then
    log_warn('Received stopped event without thread id.', { body = body })
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
    local source_path, outside_project, unsafe_source = analyze_frame_source(frame)
    set_stop_context(source_path, frame.line, outside_project, unsafe_source)

    local pending = state.pending_project_step
    log_info('Processed DAP stopped event.', {
      thread_id = state.current_thread_id,
      frame_id = state.current_frame_id,
      source = source_path,
      line = frame.line,
      outside_project = outside_project,
      unsafe_source = unsafe_source,
      pending_command = pending and pending.command or nil,
      pending_remaining = pending and pending.remaining or nil,
    })
    if pending and outside_project and pending.remaining > 0 then
      pending.remaining = pending.remaining - 1
      request_step(effective_step_command(pending.command, { project_managed = true }))
      return
    end

    state.pending_project_step = nil
    refresh_locals_and_displays()
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
  dap.listeners.after.event_initialized = dap.listeners.after.event_initialized or {}
  dap.listeners.after.event_output = dap.listeners.after.event_output or {}
  dap.listeners.before.event_stopped = dap.listeners.before.event_stopped or {}
  dap.listeners.after.event_stopped = dap.listeners.after.event_stopped or {}
  dap.listeners.before.event_continued = dap.listeners.before.event_continued or {}
  dap.listeners.before.event_exited = dap.listeners.before.event_exited or {}
  dap.listeners.before.event_terminated = dap.listeners.before.event_terminated or {}

  dap.listeners.after.event_initialized.user_dap_panels = function(session, body)
    state.session_stopped = false
    log_info('DAP session initialized.', {
      session = tostring(session),
      body = body,
    })
    pcall(function() require('user.audit').log_dap_event('initialized', body) end)
  end
  dap.listeners.after.event_output.user_dap_panels = function(_, body)
    vim.schedule(function()
      local category = body.category or 'output'
      local text = body.output or ''
      if text == '' then
        return
      end
      local lines = {}
      local prefix = '[' .. category .. '] '
      local first = true
      for chunk in text:gmatch('([^\n]*)\n?') do
        if chunk == '' and first == false then
          break
        end
        table.insert(lines, prefix .. chunk)
        first = false
      end
      append_panel_lines(state.panels.output, lines)
    end)
  end
  dap.listeners.before.event_stopped.user_dap_panels = function()
    log_info('DAP stopped event received.', {})
    pcall(function() require('user.audit').log_dap_event('stopped_before', {}) end)
    local current_win = vim.api.nvim_get_current_win()
    if not current_win or not vim.api.nvim_win_is_valid(current_win) then
      return
    end
    local current_buf = vim.api.nvim_win_get_buf(current_win)
    if is_panel_buf(current_buf) or vim.bo[current_buf].buftype ~= '' then
      focus_source_window()
    end
  end
  dap.listeners.after.event_stopped.user_dap_panels = function(session, body)
    pcall(function() require('user.audit').log_dap_event('stopped_after', body) end)
    vim.schedule(function()
      M.handle_stopped(session, body)
    end)
  end
  dap.listeners.before.event_continued.user_dap_panels = function()
    log_info('DAP continued event received.', {})
    pcall(function() require('user.audit').log_dap_event('continued', {}) end)
    clear_stop_state()
  end
  dap.listeners.before.event_exited.user_dap_panels = function(_, body)
    log_warn('DAP exited event received.', body)
    pcall(function() require('user.audit').log_dap_event('exited', body) end)
    notify_step_termination('exited')
    clear_stop_state()
    state.pending_project_step = nil
    state.last_action = nil
  end
  dap.listeners.before.event_terminated.user_dap_panels = function(_, body)
    log_warn('DAP terminated event received.', body)
    pcall(function() require('user.audit').log_dap_event('terminated', body) end)
    notify_step_termination('terminated')
    clear_stop_state()
    state.pending_project_step = nil
    state.last_action = nil
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
        state.source_winid = vim.api.nvim_get_current_win()
      end
    end,
  })

  vim.api.nvim_create_autocmd('VimResized', {
    group = vim.api.nvim_create_augroup('UserDapPanelResize', { clear = true }),
    callback = function()
      layout_panels()
      if state.popup and state.popup.winid and vim.api.nvim_win_is_valid(state.popup.winid) then
        local lines = vim.api.nvim_buf_get_lines(state.popup.bufnr, 0, -1, false)
        local width, height = popup_size(lines, 60)
        local row = math.floor((vim.o.lines - height) / 2 - 1)
        local col = math.floor((vim.o.columns - width) / 2)
        vim.api.nvim_win_set_config(state.popup.winid, {
          relative = 'editor',
          row = math.max(1, row),
          col = math.max(0, col),
          width = width,
          height = height,
        })
      end
    end,
  })

  return true
end

M._state = state
M.log_path = LOG_PATH
M.log_event = log_info

return M
