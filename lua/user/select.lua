local M = {}
local uv = vim.uv or vim.loop

function M.select(items, opts, on_choice)
  if not items or #items == 0 then
    on_choice(nil, nil)
    return
  end

  opts = opts or {}
  local prompt = opts.prompt or "Select Action"
  local format_item = opts.format_item or function(item)
    return type(item) == "string" and item or vim.inspect(item)
  end

  -- Create a scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "modifiable", true)

  local status_line = " Input: "
  local first_item_line = 2
  local lines = { status_line }
  for i, item in ipairs(items) do
    table.insert(lines, string.format(" %d. %s", i, format_item(item)))
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "readonly", true)

  -- Calculate dimensions
  local max_line_len = 0
  for _, line in ipairs(lines) do
    max_line_len = math.max(max_line_len, vim.fn.strdisplaywidth(line))
  end
  local width = math.max(60, max_line_len + 4)
  width = math.min(width, vim.o.columns - 4)
  local height = math.min(#items + 1, vim.o.lines - 4)

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " " .. prompt .. " ",
    title_pos = "center",
    footer = " [0-9]: Jump  <BS>: Back  <CR>: Run  .: Toggle/Run  q: Exit  <Esc><Esc>: Exit ",
    footer_pos = "center",
  }

  local win = vim.api.nvim_open_win(buf, true, win_opts)
  vim.api.nvim_win_set_option(win, "cursorline", true)
  vim.api.nvim_win_set_option(win, "wrap", false)

  local typed_number = ""
  local closed = false
  local last_esc_at = 0
  local ns = vim.api.nvim_create_namespace("user_select_status")
  local status_hl = vim.fn.hlexists("DiagnosticError") == 1 and "DiagnosticError" or "ErrorMsg"

  local function close()
    if closed then return end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  local function select_current()
    if closed then return end
    local line = vim.api.nvim_win_get_cursor(win)[1] - 1
    close()
    on_choice(items[line], line)
  end

  local function abort()
    close()
    on_choice(nil, nil)
  end

  local function render_status()
    if closed or not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    if vim.api.nvim_win_is_valid(win) then
      local line = vim.api.nvim_win_get_cursor(win)[1]
      if line < first_item_line then
        vim.api.nvim_win_set_cursor(win, { first_item_line, 0 })
      end
    end

    local text = " Input: " .. typed_number
    local was_readonly = vim.api.nvim_buf_get_option(buf, "readonly")

    vim.api.nvim_buf_set_option(buf, "modifiable", true)
    vim.api.nvim_buf_set_option(buf, "readonly", false)
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { text })
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
    vim.api.nvim_buf_set_option(buf, "readonly", was_readonly)

    local label_width = #(" Input: ")

    vim.api.nvim_buf_clear_namespace(buf, ns, 0, 1)
    vim.api.nvim_buf_add_highlight(buf, ns, "Title", 0, 0, #text)
    if #typed_number > 0 then
      vim.api.nvim_buf_add_highlight(buf, ns, status_hl, 0, label_width, label_width + #typed_number)
    end
  end

  local function update_cursor()
    local target = tonumber(typed_number)
    if target and target >= 1 and target <= #items then
      vim.api.nvim_win_set_cursor(win, { target + 1, 0 })
    end
    render_status()
  end

  -- Bind number keys 0-9
  for i = 0, 9 do
    vim.keymap.set("n", tostring(i), function()
      typed_number = typed_number .. tostring(i)
      update_cursor()
    end, { buffer = buf, silent = true })
  end

  -- Bind Backspace
  vim.keymap.set("n", "<BS>", function()
    if #typed_number > 0 then
      typed_number = typed_number:sub(1, -2)
    end
    local target = tonumber(typed_number)
    if target and target >= 1 and target <= #items then
      vim.api.nvim_win_set_cursor(win, { target + 1, 0 })
    end
    render_status()
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "<CR>", select_current, { buffer = buf, silent = true })
  vim.keymap.set("n", ".", select_current, { buffer = buf, silent = true })

  -- Bind q
  vim.keymap.set("n", "q", abort, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    local now = uv.now()
    if now - last_esc_at <= math.max(vim.o.timeoutlen, 250) then
      abort()
      return
    end

    last_esc_at = now
  end, { buffer = buf, silent = true, nowait = true })

  vim.api.nvim_win_set_cursor(win, { first_item_line, 0 })
  render_status()

  -- Autocmd to handle closing when buffer is left
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once = true,
    callback = function()
      close()
    end,
  })
end

function M.select_many(items, prompt, label_f, opts, on_choice)
  if not items or #items == 0 then
    on_choice({})
    return
  end

  label_f = label_f or function(item)
    return type(item) == "string" and item or vim.inspect(item)
  end
  opts = opts or {}

  local toggle_keys = vim.g.select_many_toggle_keys or { "-", "<Space>" }
  local toggle_hint = table.concat(toggle_keys, "/")

  local selected_indices = {}
  local is_selected = opts.is_selected or function(_) return false end
  for i, item in ipairs(items) do
    if is_selected(item) then
      selected_indices[i] = true
    end
  end

  -- Create a scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "modifiable", true)

  local status_line = " Input: "
  local first_item_line = 2

  -- Pre-calculate max line length for window width
  local max_line_len = vim.fn.strdisplaywidth(status_line)
  for i, item in ipairs(items) do
    local dummy_line = string.format(" %d. [ ] %s", i, label_f(item))
    max_line_len = math.max(max_line_len, vim.fn.strdisplaywidth(dummy_line))
  end

  local width = math.max(60, max_line_len + 4)
  width = math.min(width, vim.o.columns - 4)
  local height = math.min(#items + 1, vim.o.lines - 4)

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " " .. prompt .. " ",
    title_pos = "center",
    footer = " [0-9]: Jump  <BS>: Back  " .. toggle_hint .. ": Toggle  <CR>: Finish  q: Exit  <Esc><Esc>: Exit ",
    footer_pos = "center",
  }

  local win = vim.api.nvim_open_win(buf, true, win_opts)
  vim.api.nvim_win_set_option(win, "cursorline", true)
  vim.api.nvim_win_set_option(win, "wrap", false)

  local typed_number = ""
  local closed = false
  local last_esc_at = 0
  local ns = vim.api.nvim_create_namespace("user_select_many_status")
  local status_hl = vim.fn.hlexists("DiagnosticError") == 1 and "DiagnosticError" or "ErrorMsg"
  local ok_hl = vim.fn.hlexists("DiagnosticOk") == 1 and "DiagnosticOk" or "String"

  local function close()
    if closed then return end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  local function finish_selection()
    if closed then return end
    local selected_items = {}
    for i, item in ipairs(items) do
      if selected_indices[i] then
        table.insert(selected_items, item)
      end
    end
    close()
    on_choice(selected_items)
  end

  local function abort()
    close()
    on_choice({})
  end

  local function render_buffer()
    if closed or not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    local text = " Input: " .. typed_number
    local lines = { text }
    for i, item in ipairs(items) do
      local check = selected_indices[i] and "[x]" or "[ ]"
      table.insert(lines, string.format(" %d. %s %s", i, check, label_f(item)))
    end

    local was_readonly = vim.api.nvim_buf_get_option(buf, "readonly")
    vim.api.nvim_buf_set_option(buf, "modifiable", true)
    vim.api.nvim_buf_set_option(buf, "readonly", false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
    vim.api.nvim_buf_set_option(buf, "readonly", was_readonly)

    if vim.api.nvim_win_is_valid(win) then
      local line = vim.api.nvim_win_get_cursor(win)[1]
      if line < first_item_line then
        pcall(vim.api.nvim_win_set_cursor, win, { first_item_line, 0 })
      end
    end

    local label_width = #(" Input: ")

    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, ns, "Title", 0, 0, #text)
    if #typed_number > 0 then
      vim.api.nvim_buf_add_highlight(buf, ns, status_hl, 0, label_width, label_width + #typed_number)
    end

    for i = 1, #items do
      local line_idx = i
      if selected_indices[i] then
        vim.api.nvim_buf_add_highlight(buf, ns, ok_hl, line_idx, 0, -1)
      end
    end
  end

  local function update_cursor()
    local target = tonumber(typed_number)
    if target and target >= 1 and target <= #items then
      vim.api.nvim_win_set_cursor(win, { target + 1, 0 })
    end
    render_buffer()
  end

  local function toggle_choice()
    if closed then return end
    local idx
    if #typed_number > 0 then
      idx = tonumber(typed_number)
      typed_number = ""
    else
      local line = vim.api.nvim_win_get_cursor(win)[1]
      idx = line - 1
    end

    if idx and idx >= 1 and idx <= #items then
      selected_indices[idx] = not selected_indices[idx]
      render_buffer()
      if idx >= 1 and idx <= #items then
        pcall(vim.api.nvim_win_set_cursor, win, { idx + 1, 0 })
      end
    end
  end

  -- Bind number keys 0-9
  for i = 0, 9 do
    vim.keymap.set("n", tostring(i), function()
      typed_number = typed_number .. tostring(i)
      update_cursor()
    end, { buffer = buf, silent = true })
  end

  -- Bind Backspace
  vim.keymap.set("n", "<BS>", function()
    if #typed_number > 0 then
      typed_number = typed_number:sub(1, -2)
    end
    local target = tonumber(typed_number)
    if target and target >= 1 and target <= #items then
      vim.api.nvim_win_set_cursor(win, { target + 1, 0 })
    end
    render_buffer()
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "<CR>", finish_selection, { buffer = buf, silent = true })
  for _, key in ipairs(toggle_keys) do
    vim.keymap.set("n", key, toggle_choice, { buffer = buf, silent = true })
  end

  -- Bind q
  vim.keymap.set("n", "q", abort, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    local now = uv.now()
    if now - last_esc_at <= math.max(vim.o.timeoutlen, 250) then
      abort()
      return
    end
    last_esc_at = now
  end, { buffer = buf, silent = true, nowait = true })

  render_buffer()
  pcall(vim.api.nvim_win_set_cursor, win, { first_item_line, 0 })

  -- Autocmd to handle closing when buffer is left
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once = true,
    callback = function()
      close()
    end,
  })
end

return M

