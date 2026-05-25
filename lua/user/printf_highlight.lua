-- [[ user.printf_highlight ]]
-- Treesitter-based C printf format placeholder and argument highlighting

local M = {}

-- Namespace for highlighting
local ns_id = vim.api.nvim_create_namespace('printf_highlight')

-- Define our premium highlight groups linked to MatchParen by default
vim.api.nvim_set_hl(0, 'PrintfPlaceholder', { link = 'MatchParen', default = true })
vim.api.nvim_set_hl(0, 'PrintfArgument', { link = 'MatchParen', default = true })

-- Standard printf-like functions and the 0-based index of their format string argument
local printf_funcs = {
  printf = 0,
  fprintf = 1,
  sprintf = 1,
  snprintf = 2,
  dprintf = 1,
  syslog = 1,
  panic = 0,
}

-- Walk up from the given node to find a 'call_expression' node
local function get_call_expression(node)
  local current = node
  while current do
    if current:type() == 'call_expression' then
      return current
    end
    current = current:parent()
  end
  return nil
end

-- Helper to check if a cursor position is inside a treesitter node's range
local function is_cursor_in_range(cursor_row, cursor_col, s_row, s_col, e_row, e_col)
  if cursor_row < s_row or cursor_row > e_row then
    return false
  end
  if cursor_row == s_row and cursor_col < s_col then
    return false
  end
  if cursor_row == e_row and cursor_col >= e_col then
    return false
  end
  return true
end

-- Helper to convert 1-based byte offset in text to 0-based buffer (row, col)
local function offset_to_pos(text, start_row, start_col, offset)
  local current_offset = 1
  local row = start_row
  local col = start_col
  local len = #text

  while current_offset < offset and current_offset <= len do
    local char = text:sub(current_offset, current_offset)
    if char == '\n' then
      row = row + 1
      col = 0
    else
      col = col + 1
    end
    current_offset = current_offset + 1
  end

  return row, col
end

-- Helper to convert 0-based buffer (row, col) to 1-based byte offset in text
local function pos_to_offset(text, start_row, start_col, target_row, target_col)
  local current_offset = 1
  local row = start_row
  local col = start_col
  local len = #text

  while current_offset <= len do
    if row == target_row and col == target_col then
      return current_offset
    end

    local char = text:sub(current_offset, current_offset)
    if char == '\n' then
      row = row + 1
      col = 0
    else
      col = col + 1
    end
    current_offset = current_offset + 1
  end

  return nil
end

-- Parse format string to find all argument-consuming components (stars and specifiers)
-- Returns a list of placeholders with start_offset and end_offset relative to the inner string content
local function parse_format_string(str)
  local placeholders = {}
  local i = 1
  local len = #str

  while i <= len do
    local char = str:sub(i, i)
    if char == '%' then
      if str:sub(i + 1, i + 1) == '%' then
        -- Escaped '%', skip it
        i = i + 2
      else
        -- Found a potential placeholder!
        local start_idx = i
        i = i + 1

        -- Parse flags: zero or more of: '-', '+', ' ', '#', '0', '\''
        while i <= len and (str:sub(i, i):find("[-+ #0']")) do
          i = i + 1
        end

        -- Parse width: [0-9]+ or '*'
        if i <= len and str:sub(i, i) == '*' then
          table.insert(placeholders, {
            type = 'star',
            start_offset = i,
            end_offset = i,
          })
          i = i + 1
        else
          while i <= len and str:sub(i, i):find("[0-9]") do
            i = i + 1
          end
        end

        -- Parse precision: '.' followed by ([0-9]+ or '*')
        if i <= len and str:sub(i, i) == '.' then
          i = i + 1
          if i <= len and str:sub(i, i) == '*' then
            table.insert(placeholders, {
              type = 'star',
              start_offset = i,
              end_offset = i,
            })
            i = i + 1
          else
            while i <= len and str:sub(i, i):find("[0-9]") do
              i = i + 1
            end
          end
        end

        -- Parse length modifier: 'hh', 'h', 'l', 'll', 'j', 'z', 't', 'L', 'I64', 'I32'
        if i <= len then
          local two = str:sub(i, i + 1)
          if two == 'hh' or two == 'll' or two == 'I64' or two == 'I32' then
            i = i + 2
          elseif str:sub(i, i):find("[hljztL]") then
            i = i + 1
          end
        end

        -- Parse specifier: one of: 'd', 'i', 'u', 'o', 'x', 'X', 'f', 'F', 'e', 'E', 'g', 'G', 'a', 'A', 'c', 's', 'p', 'n'
        if i <= len then
          local specifier = str:sub(i, i)
          if specifier:find("[diuoxXfFeEgGaAcspn]") then
            table.insert(placeholders, {
              type = 'specifier',
              start_offset = start_idx,
              end_offset = i,
              specifier = specifier,
            })
            i = i + 1
          else
            -- Backtrack and treat '%' as literal
            i = start_idx + 1
          end
        else
          i = start_idx + 1
        end
      end
    else
      i = i + 1
    end
  end
  return placeholders
end

-- Safely highlight a given buffer range (works across single or multiple lines)
local function highlight_range(bufnr, s_row, s_col, e_row, e_col, hl_group)
  if s_row == e_row then
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl_group, s_row, s_col, e_col)
  else
    -- Multi-line highlight
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl_group, s_row, s_col, -1)
    for r = s_row + 1, e_row - 1 do
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl_group, r, 0, -1)
    end
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl_group, e_row, 0, e_col)
  end
end

-- Clear all highlights in the namespace
function M.clear_highlights(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr or 0) then
    vim.api.nvim_buf_clear_namespace(bufnr or 0, ns_id, 0, -1)
  end
end

-- Core highlight update logic
function M.update_highlights(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Clear previous highlights first
  M.clear_highlights(bufnr)

  -- Get current cursor position (1-based row, 0-based col)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_row = cursor_pos[1] - 1
  local cursor_col = cursor_pos[2]

  -- Get treesitter node at cursor
  local node = nil
  if vim.treesitter.get_node then
    node = vim.treesitter.get_node()
  else
    local ok, ts_utils = pcall(require, 'nvim-treesitter.ts_utils')
    if ok then
      node = ts_utils.get_node_at_cursor()
    end
  end

  if not node then
    return
  end

  -- Find call expression ancestor
  local call_expr = get_call_expression(node)
  if not call_expr then
    return
  end

  -- Get function name
  local func_node = call_expr:field('function')[1] or call_expr:child(0)
  if not func_node then
    return
  end
  local func_name = vim.treesitter.get_node_text(func_node, bufnr)

  -- Find argument list child
  local arg_list_node = nil
  for i = 0, call_expr:child_count() - 1 do
    local child = call_expr:child(i)
    if child:type() == 'argument_list' then
      arg_list_node = child
      break
    end
  end

  if not arg_list_node then
    return
  end

  -- Gather all arguments in the list
  local args = {}
  for i = 0, arg_list_node:named_child_count() - 1 do
    table.insert(args, arg_list_node:named_child(i))
  end

  if #args == 0 then
    return
  end

  -- Determine format string index (1-based for Lua)
  local format_idx = nil
  local known_idx = printf_funcs[func_name]
  if known_idx then
    format_idx = known_idx + 1
  else
    -- Heuristic fallback: search for the first string literal containing a '%' character
    for i, arg in ipairs(args) do
      local arg_type = arg:type()
      if arg_type == 'string_literal' or arg_type == 'concatenated_string' then
        local text = vim.treesitter.get_node_text(arg, bufnr)
        if text:find('%%') then
          format_idx = i
          break
        end
      end
    end

    -- Ultimate fallback: just pick the first string literal argument
    if not format_idx then
      for i, arg in ipairs(args) do
        local arg_type = arg:type()
        if arg_type == 'string_literal' or arg_type == 'concatenated_string' then
          format_idx = i
          break
        end
      end
    end
  end

  -- If no format string argument was found, or format_idx is out of range, stop
  if not format_idx or format_idx > #args then
    return
  end

  local format_node = args[format_idx]
  if format_node:type() ~= 'string_literal' then
    return
  end

  -- Get format string range and text
  local f_start_row, f_start_col, f_end_row, f_end_col = format_node:range()
  local format_text = vim.treesitter.get_node_text(format_node, bufnr)

  -- Strip opening and closing quotes (standard C strings have " at start and end)
  if format_text:sub(1, 1) ~= '"' or format_text:sub(-1, -1) ~= '"' then
    return
  end
  local format_content = format_text:sub(2, -2)

  -- Parse placeholders
  local placeholders = parse_format_string(format_content)
  if #placeholders == 0 then
    return
  end

  -- Separate arguments after the format string
  local arg_values = {}
  for i = format_idx + 1, #args do
    table.insert(arg_values, args[i])
  end

  -- Symmetrically highlight based on cursor position
  if is_cursor_in_range(cursor_row, cursor_col, f_start_row, f_start_col, f_end_row, f_end_col) then
    -- Cursor is inside the format string. Find if it's on a placeholder.
    local cursor_offset = pos_to_offset(format_text, f_start_row, f_start_col, cursor_row, cursor_col)
    if not cursor_offset then
      return
    end

    -- Offset inside format_content (subtract 1 for the leading quote)
    local content_offset = cursor_offset - 1

    for k, p in ipairs(placeholders) do
      if content_offset >= p.start_offset and content_offset <= p.end_offset then
        -- Cursor is on this placeholder!
        -- Highlight the placeholder
        local p_start_row, p_start_col = offset_to_pos(format_text, f_start_row, f_start_col, p.start_offset + 1)
        local p_end_row, p_end_col = offset_to_pos(format_text, f_start_row, f_start_col, p.end_offset + 2)
        highlight_range(bufnr, p_start_row, p_start_col, p_end_row, p_end_col, 'PrintfPlaceholder')

        -- Highlight corresponding argument (if exists)
        local corresponding_arg = arg_values[k]
        if corresponding_arg then
          local a_start_row, a_start_col, a_end_row, a_end_col = corresponding_arg:range()
          highlight_range(bufnr, a_start_row, a_start_col, a_end_row, a_end_col, 'PrintfArgument')
        end
        break
      end
    end
  else
    -- Cursor is outside the format string. Check if it's inside any of the argument expressions.
    for k, arg_node in ipairs(arg_values) do
      local a_start_row, a_start_col, a_end_row, a_end_col = arg_node:range()
      if is_cursor_in_range(cursor_row, cursor_col, a_start_row, a_start_col, a_end_row, a_end_col) then
        -- Cursor is on this argument!
        -- Highlight the argument
        highlight_range(bufnr, a_start_row, a_start_col, a_end_row, a_end_col, 'PrintfArgument')

        -- Highlight the corresponding placeholder (if exists)
        local p = placeholders[k]
        if p then
          local p_start_row, p_start_col = offset_to_pos(format_text, f_start_row, f_start_col, p.start_offset + 1)
          local p_end_row, p_end_col = offset_to_pos(format_text, f_start_row, f_start_col, p.end_offset + 2)
          highlight_range(bufnr, p_start_row, p_start_col, p_end_row, p_end_col, 'PrintfPlaceholder')
        end
        break
      end
    end
  end
end

-- Initialize the plugin and register the autocommands
function M.setup()
  local group = vim.api.nvim_create_augroup('PrintfHighlight', { clear = true })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = { 'c', 'cpp' },
    callback = function(args)
      local bufnr = args.buf
      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        group = group,
        buffer = bufnr,
        callback = function()
          M.update_highlights(bufnr)
        end,
      })
      vim.api.nvim_create_autocmd({ 'BufLeave', 'InsertLeave' }, {
        group = group,
        buffer = bufnr,
        callback = function()
          M.clear_highlights(bufnr)
        end,
      })
    end,
  })
end

return M
