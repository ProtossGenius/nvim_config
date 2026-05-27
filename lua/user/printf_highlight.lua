-- [[ user.printf_highlight ]]
-- Treesitter-based printf/log placeholder and argument highlighting

local M = {}

local ns_id = vim.api.nvim_create_namespace('printf_highlight')
M.ns_id = ns_id

vim.api.nvim_set_hl(0, 'PrintfPlaceholder', { link = 'MatchParen', default = true })
vim.api.nvim_set_hl(0, 'PrintfArgument', { link = 'MatchParen', default = true })

local supported_filetypes = {
  c = { call_expression = true },
  cpp = { call_expression = true },
  go = { call_expression = true },
  java = { method_invocation = true },
  lua = { function_call = true },
  python = { call = true },
  rust = { macro_invocation = true },
  javascript = { call_expression = true },
  javascriptreact = { call_expression = true },
  typescript = { call_expression = true },
  typescriptreact = { call_expression = true },
}

local arg_container_types = {
  argument_list = true,
  arguments = true,
  token_tree = true,
}

local string_node_types = {
  concatenated_string = true,
  interpreted_string_literal = true,
  string = true,
  string_literal = true,
}

local java_brace_methods = {
  debug = true,
  error = true,
  info = true,
  trace = true,
  warn = true,
}

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

local function highlight_range(bufnr, s_row, s_col, e_row, e_col, hl_group)
  if s_row == e_row then
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl_group, s_row, s_col, e_col)
    return
  end

  vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl_group, s_row, s_col, -1)
  for row = s_row + 1, e_row - 1 do
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl_group, row, 0, -1)
  end
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl_group, e_row, 0, e_col)
end

local function node_text(bufnr, start_row, start_col, end_row, end_col)
  return table.concat(vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {}), '\n')
end

local function get_current_node()
  if vim.treesitter.get_node then
    return vim.treesitter.get_node()
  end

  local ok, ts_utils = pcall(require, 'nvim-treesitter.ts_utils')
  if ok then
    return ts_utils.get_node_at_cursor()
  end
end

local function get_call_expression(node, filetype)
  local valid_types = supported_filetypes[filetype]
  if not valid_types then
    return nil
  end

  local current = node
  while current do
    if valid_types[current:type()] then
      return current
    end
    current = current:parent()
  end

  return nil
end

local function get_argument_container(call_node)
  for index = 0, call_node:named_child_count() - 1 do
    local child = call_node:named_child(index)
    if arg_container_types[child:type()] then
      return child
    end
  end
end

local function get_arguments(arg_container)
  local args = {}
  for index = 0, arg_container:named_child_count() - 1 do
    table.insert(args, arg_container:named_child(index))
  end
  return args
end

local function get_callee_text(call_node, arg_container, bufnr)
  local call_start_row, call_start_col = call_node:range()
  local arg_start_row, arg_start_col = arg_container:range()
  local text = node_text(bufnr, call_start_row, call_start_col, arg_start_row, arg_start_col)
  return vim.trim(text)
end

local function parse_percent_placeholders(str)
  local placeholders = {}
  local index = 1
  local len = #str

  while index <= len do
    local char = str:sub(index, index)
    if char ~= '%' then
      index = index + 1
    elseif str:sub(index + 1, index + 1) == '%' then
      index = index + 2
    else
      local start_idx = index
      index = index + 1

      while index <= len and str:sub(index, index):find("[-+ #0']") do
        index = index + 1
      end

      if str:sub(index, index) == '*' then
        table.insert(placeholders, {
          type = 'star',
          start_offset = index,
          end_offset = index,
        })
        index = index + 1
      else
        while index <= len and str:sub(index, index):find('[0-9]') do
          index = index + 1
        end
      end

      if str:sub(index, index) == '.' then
        index = index + 1
        if str:sub(index, index) == '*' then
          table.insert(placeholders, {
            type = 'star',
            start_offset = index,
            end_offset = index,
          })
          index = index + 1
        else
          while index <= len and str:sub(index, index):find('[0-9]') do
            index = index + 1
          end
        end
      end

      if index <= len then
        local two_chars = str:sub(index, index + 1)
        if two_chars == 'hh' or two_chars == 'll' or two_chars == 'I64' or two_chars == 'I32' then
          index = index + 2
        elseif str:sub(index, index):find('[hljztL]') then
          index = index + 1
        end
      end

      if index <= len and str:sub(index, index):find('[diuoxXfFeEgGaAcspnqvTt%b]') then
        table.insert(placeholders, {
          type = 'specifier',
          start_offset = start_idx,
          end_offset = index,
        })
        index = index + 1
      else
        index = start_idx + 1
      end
    end
  end

  return placeholders
end

local function parse_brace_placeholders(str, opts)
  opts = opts or {}
  local placeholders = {}
  local index = 1
  local len = #str

  while index <= len do
    local char = str:sub(index, index)
    local next_char = str:sub(index + 1, index + 1)
    local prev_char = index > 1 and str:sub(index - 1, index - 1) or ''

    if char == '{' and next_char == '{' then
      index = index + 2
    elseif char == '}' and next_char == '}' then
      index = index + 2
    elseif char == '{' and opts.slash_escape and prev_char == '\\' then
      index = index + 1
    elseif char == '{' then
      local end_index = index + 1
      while end_index <= len and str:sub(end_index, end_index) ~= '}' do
        end_index = end_index + 1
      end

      if end_index <= len then
        local placeholder_text = str:sub(index, end_index)
        if not opts.empty_only or placeholder_text == '{}' then
          table.insert(placeholders, {
            type = 'brace',
            start_offset = index,
            end_offset = end_index,
          })
        end
        index = end_index + 1
      else
        index = index + 1
      end
    else
      index = index + 1
    end
  end

  return placeholders
end

local function get_string_info(node, bufnr)
  if not string_node_types[node:type()] then
    return nil
  end

  local raw_text = vim.treesitter.get_node_text(node, bufnr)
  local quote_start, quote_len, quote_end_len

  if raw_text:sub(1, 1) == '`' and raw_text:sub(-1, -1) == '`' then
    quote_start = 1
    quote_len = 1
    quote_end_len = 1
  else
    local prefix = raw_text:match('^[rRuUbBfF]*') or ''
    local rest = raw_text:sub(#prefix + 1)

    if rest:sub(1, 3) == '"""' and rest:sub(-3) == '"""' then
      quote_start = #prefix + 1
      quote_len = 3
      quote_end_len = 3
    elseif rest:sub(1, 3) == "'''" and rest:sub(-3) == "'''" then
      quote_start = #prefix + 1
      quote_len = 3
      quote_end_len = 3
    elseif (rest:sub(1, 1) == '"' or rest:sub(1, 1) == "'") and rest:sub(-1, -1) == rest:sub(1, 1) then
      quote_start = #prefix + 1
      quote_len = 1
      quote_end_len = 1
    end
  end

  if not quote_start then
    return nil
  end

  local content_start = quote_start + quote_len
  local content_end = #raw_text - quote_end_len
  if content_end < content_start - 1 then
    return nil
  end

  local start_row, start_col = node:range()
  return {
    content = raw_text:sub(content_start, content_end),
    content_start_offset = content_start,
    raw_text = raw_text,
    start_col = start_col,
    start_row = start_row,
  }
end

local function contains_percent_placeholders(text)
  return #parse_percent_placeholders(text) > 0
end

local function contains_brace_placeholders(text, opts)
  return #parse_brace_placeholders(text, opts) > 0
end

local function is_java_brace_call(callee_text)
  local method = callee_text:match('([%w_]+)$')
  return method and java_brace_methods[method:lower()] or false
end

local function allow_percent_style(filetype, callee_text)
  local lower = callee_text:lower()

  if filetype == 'java' then
    return lower:find('printf', 1, true) ~= nil or lower:find('format', 1, true) ~= nil
  end

  if filetype == 'javascript' or filetype == 'javascriptreact' or filetype == 'typescript' or filetype == 'typescriptreact' then
    return lower:find('console.', 1, true) ~= nil
      or lower:find('util.format', 1, true) ~= nil
      or lower:find('printf', 1, true) ~= nil
      or lower:find('format', 1, true) ~= nil
  end

  if filetype == 'lua' then
    return lower == 'string.format' or lower:find('format', 1, true) ~= nil
  end

  if filetype == 'rust' then
    return false
  end

  return true
end

local function brace_options(filetype, callee_text)
  if filetype == 'rust' then
    return {
      allowed = true,
      empty_only = false,
      slash_escape = false,
    }
  end

  if filetype == 'java' and is_java_brace_call(callee_text) then
    return {
      allowed = true,
      empty_only = true,
      slash_escape = true,
    }
  end

  return { allowed = false }
end

local function resolve_format_call(bufnr, filetype, callee_text, args)
  for index, arg in ipairs(args) do
    local string_info = get_string_info(arg, bufnr)
    if string_info then
      local has_following_args = index < #args
      if has_following_args and allow_percent_style(filetype, callee_text) and contains_percent_placeholders(string_info.content) then
        return {
          format_idx = index,
          parser = parse_percent_placeholders,
          parser_opts = nil,
          string_info = string_info,
        }
      end

      local brace_opts = brace_options(filetype, callee_text)
      if has_following_args and brace_opts.allowed and contains_brace_placeholders(string_info.content, brace_opts) then
        return {
          format_idx = index,
          parser = parse_brace_placeholders,
          parser_opts = brace_opts,
          string_info = string_info,
        }
      end
    end
  end
end

function M.clear_highlights(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr or 0) then
    vim.api.nvim_buf_clear_namespace(bufnr or 0, ns_id, 0, -1)
  end
end

function M.update_highlights(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  M.clear_highlights(bufnr)

  local filetype = vim.bo[bufnr].filetype
  if not supported_filetypes[filetype] then
    return
  end

  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_row = cursor_pos[1] - 1
  local cursor_col = cursor_pos[2]
  local node = get_current_node()
  if not node then
    return
  end

  local call_expr = get_call_expression(node, filetype)
  if not call_expr then
    return
  end

  local arg_container = get_argument_container(call_expr)
  if not arg_container then
    return
  end

  local args = get_arguments(arg_container)
  if #args == 0 then
    return
  end

  local callee_text = get_callee_text(call_expr, arg_container, bufnr)
  if callee_text == '' then
    return
  end

  local resolved = resolve_format_call(bufnr, filetype, callee_text, args)
  if not resolved or resolved.format_idx > #args then
    return
  end

  local format_node = args[resolved.format_idx]
  local string_info = resolved.string_info
  local placeholders = resolved.parser(string_info.content, resolved.parser_opts)
  if #placeholders == 0 then
    return
  end

  local format_start_row, format_start_col, format_end_row, format_end_col = format_node:range()
  local arg_values = {}
  for index = resolved.format_idx + 1, #args do
    table.insert(arg_values, args[index])
  end

  if is_cursor_in_range(cursor_row, cursor_col, format_start_row, format_start_col, format_end_row, format_end_col) then
    local cursor_offset = pos_to_offset(string_info.raw_text, string_info.start_row, string_info.start_col, cursor_row, cursor_col)
    if not cursor_offset then
      return
    end

    local content_offset = cursor_offset - string_info.content_start_offset + 1
    if content_offset < 1 then
      return
    end

    for placeholder_index, placeholder in ipairs(placeholders) do
      if content_offset >= placeholder.start_offset and content_offset <= placeholder.end_offset then
        local placeholder_start_offset = string_info.content_start_offset + placeholder.start_offset - 1
        local placeholder_end_offset = string_info.content_start_offset + placeholder.end_offset
        local p_start_row, p_start_col = offset_to_pos(string_info.raw_text, string_info.start_row, string_info.start_col, placeholder_start_offset)
        local p_end_row, p_end_col = offset_to_pos(string_info.raw_text, string_info.start_row, string_info.start_col, placeholder_end_offset)
        highlight_range(bufnr, p_start_row, p_start_col, p_end_row, p_end_col, 'PrintfPlaceholder')

        local arg_node = arg_values[placeholder_index]
        if arg_node then
          local a_start_row, a_start_col, a_end_row, a_end_col = arg_node:range()
          highlight_range(bufnr, a_start_row, a_start_col, a_end_row, a_end_col, 'PrintfArgument')
        end
        break
      end
    end
  else
    for placeholder_index, arg_node in ipairs(arg_values) do
      local a_start_row, a_start_col, a_end_row, a_end_col = arg_node:range()
      if is_cursor_in_range(cursor_row, cursor_col, a_start_row, a_start_col, a_end_row, a_end_col) then
        highlight_range(bufnr, a_start_row, a_start_col, a_end_row, a_end_col, 'PrintfArgument')

        local placeholder = placeholders[placeholder_index]
        if placeholder then
          local placeholder_start_offset = string_info.content_start_offset + placeholder.start_offset - 1
          local placeholder_end_offset = string_info.content_start_offset + placeholder.end_offset
          local p_start_row, p_start_col = offset_to_pos(string_info.raw_text, string_info.start_row, string_info.start_col, placeholder_start_offset)
          local p_end_row, p_end_col = offset_to_pos(string_info.raw_text, string_info.start_row, string_info.start_col, placeholder_end_offset)
          highlight_range(bufnr, p_start_row, p_start_col, p_end_row, p_end_col, 'PrintfPlaceholder')
        end
        break
      end
    end
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup('PrintfHighlight', { clear = true })
  local filetypes = vim.tbl_keys(supported_filetypes)

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = filetypes,
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
