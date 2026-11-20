-- [[ user.printf_highlight ]]
-- Treesitter-based printf/log placeholder and argument highlighting

local correspondence = require('user.correspondence')

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
  raw_string_literal = true,
  string = true,
  string_literal = true,
  template_string = true,
}

local java_brace_methods = {
  debug = true,
  error = true,
  info = true,
  trace = true,
  warn = true,
}

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

local function highlight_range(bufnr, s_row, s_col, e_row, e_col, hl_group)
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, s_row, s_col, {
    end_row = e_row,
    end_col = e_col,
    hl_group = hl_group,
    strict = false,
  })
end

local function node_text(bufnr, start_row, start_col, end_row, end_col)
  local ok, lines = pcall(vim.api.nvim_buf_get_text, bufnr, start_row, start_col, end_row, end_col, {})
  if not ok or not lines then
    return ''
  end
  return table.concat(lines, '\n')
end

local function percent_specifier_pattern(filetype)
  if filetype == 'java' then
    return '[diuoxXfFeEgGaAcCsSbBhHtT]'
  elseif filetype == 'python' then
    return '[diuoxXfFeEgGaAcspnqvTtbr]'
  elseif filetype == 'go' then
    return '[diuoxXfFeEgGaAcspnqvTtbw]'
  elseif filetype == 'javascript' or filetype == 'javascriptreact'
    or filetype == 'typescript' or filetype == 'typescriptreact' then
    return '[diuoxXfFeEgGaAcspnqvTtbOj]'
  end
  return '[diuoxXfFeEgGaAcspnqvTtb]'
end

local function consume_positional_index(str, index, filetype)
  local pos_digits = str:match('^([0-9]+)%$', index)
  if pos_digits then
    return tonumber(pos_digits), index + #pos_digits + 1
  end

  if filetype == 'go' then
    local go_digits = str:match('^%[([0-9]+)%]', index)
    if go_digits then
      return tonumber(go_digits), index + #go_digits + 2
    end
  end

  return nil, index
end

local function parse_percent_placeholders(str, opts, start_arg_index)
  opts = opts or {}
  local filetype = opts.filetype
  local spec_pat = percent_specifier_pattern(filetype)
  local flag_pat = (filetype == 'java') and "[-+ #0',(]" or "[-+ #0']"
  local placeholders = {}
  local index = 1
  local len = #str
  local next_arg_index = start_arg_index or 1

  while index <= len do
    local char = str:sub(index, index)
    if char ~= '%' then
      index = index + 1
    elseif str:sub(index + 1, index + 1) == '%' then
      index = index + 2
    else
      local start_idx = index
      local saved_count = #placeholders
      local saved_next_arg = next_arg_index
      index = index + 1

      local explicit_arg
      explicit_arg, index = consume_positional_index(str, index, filetype)

      while index <= len and str:sub(index, index):find(flag_pat) do
        index = index + 1
      end

      if not explicit_arg then
        explicit_arg, index = consume_positional_index(str, index, filetype)
      end

      if str:sub(index, index) == '*' then
        local star_start = index
        index = index + 1
        local star_explicit
        star_explicit, index = consume_positional_index(str, index, filetype)
        local star_arg = star_explicit
        if not star_arg then
          star_arg = next_arg_index
          next_arg_index = next_arg_index + 1
        end
        table.insert(placeholders, {
          type = 'star',
          start_offset = star_start,
          end_offset = index - 1,
          arg_index = star_arg,
        })
      else
        while index <= len and str:sub(index, index):find('[0-9]') do
          index = index + 1
        end
      end

      if str:sub(index, index) == '.' then
        index = index + 1
        if str:sub(index, index) == '*' then
          local star_start = index
          index = index + 1
          local star_explicit
          star_explicit, index = consume_positional_index(str, index, filetype)
          local star_arg = star_explicit
          if not star_arg then
            star_arg = next_arg_index
            next_arg_index = next_arg_index + 1
          end
          table.insert(placeholders, {
            type = 'star',
            start_offset = star_start,
            end_offset = index - 1,
            arg_index = star_arg,
          })
        else
          while index <= len and str:sub(index, index):find('[0-9]') do
            index = index + 1
          end
        end
      end

      if filetype == 'go' and not explicit_arg then
        explicit_arg, index = consume_positional_index(str, index, filetype)
      end

      if index <= len then
        local three_chars = str:sub(index, index + 2)
        local two_chars = str:sub(index, index + 1)
        if three_chars == 'I64' or three_chars == 'I32' then
          index = index + 3
        elseif two_chars == 'hh' or two_chars == 'll' then
          index = index + 2
        elseif str:sub(index, index):find('[hljztL]') then
          index = index + 1
        end
      end

      if filetype == 'java' and index <= len and str:sub(index, index) == 'n' then
        while #placeholders > saved_count do
          table.remove(placeholders)
        end
        next_arg_index = saved_next_arg
        index = index + 1
      elseif index <= len and str:sub(index, index):find(spec_pat) then
        local end_idx = index
        if filetype == 'java'
          and (str:sub(index, index) == 't' or str:sub(index, index) == 'T')
          and index + 1 <= len
          and str:sub(index + 1, index + 1):find('%a') then
          end_idx = index + 1
        end

        local arg_idx = explicit_arg
        if not arg_idx then
          arg_idx = next_arg_index
          next_arg_index = next_arg_index + 1
        end

        table.insert(placeholders, {
          type = 'specifier',
          start_offset = start_idx,
          end_offset = end_idx,
          arg_index = arg_idx,
        })
        index = end_idx + 1
      else
        while #placeholders > saved_count do
          table.remove(placeholders)
        end
        next_arg_index = saved_next_arg
        index = start_idx + 1
      end
    end
  end

  return placeholders, next_arg_index
end

local function count_preceding_backslashes(str, idx)
  local count = 0
  local pos = idx - 1
  while pos >= 1 and str:sub(pos, pos) == '\\' do
    count = count + 1
    pos = pos - 1
  end
  return count
end

local function is_slf4j_brace_escaped(str, idx)
  local raw_slashes = count_preceding_backslashes(str, idx)
  return raw_slashes % 2 == 1 or math.floor(raw_slashes / 2) % 2 == 1
end

local function parse_brace_placeholders(str, opts, start_arg_index)
  opts = opts or {}
  local placeholders = {}
  local index = 1
  local len = #str
  local next_arg_index = start_arg_index or 1

  if opts.empty_only then
    while index <= len do
      local char = str:sub(index, index)
      local next_char = str:sub(index + 1, index + 1)
      if char == '{' and next_char == '}' then
        if not (opts.slash_escape and is_slf4j_brace_escaped(str, index)) then
          table.insert(placeholders, {
            type = 'brace',
            start_offset = index,
            end_offset = index + 1,
            arg_index = next_arg_index,
          })
          next_arg_index = next_arg_index + 1
        end
        index = index + 2
      else
        index = index + 1
      end
    end
    return placeholders, next_arg_index
  end

  local double_escape = opts.double_brace_escape ~= false
  while index <= len do
    local char = str:sub(index, index)
    local next_char = str:sub(index + 1, index + 1)

    if double_escape and char == '{' and next_char == '{' then
      index = index + 2
    elseif double_escape and char == '}' and next_char == '}' then
      index = index + 2
    elseif char == '{' then
      local end_index = index + 1
      local hit_open = false
      while end_index <= len do
        local ch = str:sub(end_index, end_index)
        if ch == '}' then
          break
        elseif ch == '{' then
          hit_open = true
          break
        end
        end_index = end_index + 1
      end

      if hit_open then
        index = end_index
      elseif end_index <= len then
        local inner = str:sub(index + 1, end_index - 1)
        local head = inner:match('^([^:!]*)') or ''
        local arg_idx
        if head == '' then
          arg_idx = next_arg_index
          next_arg_index = next_arg_index + 1
        elseif head:match('^[0-9]+$') then
          arg_idx = tonumber(head) + 1
        end

        if arg_idx then
          table.insert(placeholders, {
            type = 'brace',
            start_offset = index,
            end_offset = end_index,
            arg_index = arg_idx,
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

  return placeholders, next_arg_index
end

local function extract_single_string_segment(node, bufnr)
  if not string_node_types[node:type()] then
    return nil
  end

  local raw_text = vim.treesitter.get_node_text(node, bufnr)
  local start_row, start_col, end_row, end_col = node:range()
  local content, content_start

  if raw_text:sub(1, 1) == '`' and raw_text:sub(-1, -1) == '`' and #raw_text >= 2 then
    content_start = 2
    content = raw_text:sub(2, -2)
  else
    local eqs = raw_text:match('^%[(=*)%[')
    if eqs then
      local close = ']' .. eqs .. ']'
      if #raw_text >= (#eqs + 2) * 2 and raw_text:sub(-#close) == close then
        content_start = #eqs + 3
        content = raw_text:sub(content_start, #raw_text - #close)
      end
    else
      local rust_prefix, hashes = raw_text:match('^(b?r)(#*)"')
      if rust_prefix then
        local close = '"' .. hashes
        if #raw_text >= #rust_prefix + #hashes * 2 + 2 and raw_text:sub(-#close) == close then
          content_start = #rust_prefix + #hashes + 2
          content = raw_text:sub(content_start, #raw_text - #close)
        end
      else
        local cpp_prefix, delim, body, end_delim = raw_text:match('^([uUL8]*R)"([^%(%)\\%s]*)%((.*)%)([^%(%)\\%s]*)"$')
        if cpp_prefix and delim == end_delim then
          content_start = #cpp_prefix + #delim + 3
          content = body
        end
      end
    end
  end

  if not content_start then
    local prefix = raw_text:match('^[rRuUbBfFL8]*') or ''
    local rest = raw_text:sub(#prefix + 1)
    local quote_len

    if rest:sub(1, 3) == '"""' and rest:sub(-3) == '"""' and #rest >= 6 then
      quote_len = 3
    elseif rest:sub(1, 3) == "'''" and rest:sub(-3) == "'''" and #rest >= 6 then
      quote_len = 3
    elseif (rest:sub(1, 1) == '"' or rest:sub(1, 1) == "'") and #rest >= 2 and rest:sub(-1, -1) == rest:sub(1, 1) then
      quote_len = 1
    end

    if quote_len then
      content_start = #prefix + quote_len + 1
      content = raw_text:sub(content_start, #raw_text - quote_len)
    end
  end

  if not content_start or content == nil then
    return nil
  end

  return {
    content = content,
    content_start_offset = content_start,
    raw_text = raw_text,
    start_row = start_row,
    start_col = start_col,
    end_row = end_row,
    end_col = end_col,
  }
end

local function has_plus_operator(node)
  for i = 0, node:child_count() - 1 do
    if node:child(i):type() == '+' then
      return true
    end
  end
  return false
end

local function extract_format_segments(node, bufnr)
  local ntype = node:type()

  if ntype == 'concatenated_string' then
    local segments = {}
    for i = 0, node:named_child_count() - 1 do
      local child = node:named_child(i)
      local ctype = child:type()
      if ctype ~= 'comment' and ctype ~= 'line_comment' and ctype ~= 'block_comment' then
        local child_segs = extract_format_segments(child, bufnr)
        if child_segs then
          vim.list_extend(segments, child_segs)
        end
      end
    end
    return #segments > 0 and segments or nil
  end

  if ntype == 'binary_expression' then
    if not has_plus_operator(node) or node:named_child_count() < 2 then
      return nil
    end
    local left_segs = extract_format_segments(node:named_child(0), bufnr)
    local right_segs = extract_format_segments(node:named_child(1), bufnr)
    if not left_segs or not right_segs then
      return nil
    end
    vim.list_extend(left_segs, right_segs)
    return left_segs
  end

  if ntype == 'template_string' then
    local has_subst = false
    for i = 0, node:named_child_count() - 1 do
      if node:named_child(i):type() == 'template_substitution' then
        has_subst = true
        break
      end
    end
    if has_subst then
      local segments = {}
      for i = 0, node:named_child_count() - 1 do
        local child = node:named_child(i)
        if child:type() == 'string_fragment' then
          local text = vim.treesitter.get_node_text(child, bufnr)
          local sr, sc, er, ec = child:range()
          table.insert(segments, {
            content = text,
            content_start_offset = 1,
            raw_text = text,
            start_row = sr,
            start_col = sc,
            end_row = er,
            end_col = ec,
          })
        end
      end
      return #segments > 0 and segments or nil
    end
  end

  local seg = extract_single_string_segment(node, bufnr)
  if seg then
    return { seg }
  end

  return nil
end

local function parse_format_placeholders(segments, parser, parser_opts)
  local all_placeholders = {}
  local next_arg_index = 1

  for _, seg in ipairs(segments) do
    local seg_placeholders
    seg_placeholders, next_arg_index = parser(seg.content, parser_opts, next_arg_index)
    for _, placeholder in ipairs(seg_placeholders) do
      local abs_start = seg.content_start_offset + placeholder.start_offset - 1
      local abs_end = seg.content_start_offset + placeholder.end_offset
      local sr, sc = offset_to_pos(seg.raw_text, seg.start_row, seg.start_col, abs_start)
      local er, ec = offset_to_pos(seg.raw_text, seg.start_row, seg.start_col, abs_end)
      table.insert(all_placeholders, {
        type = placeholder.type,
        arg_index = placeholder.arg_index,
        start_row = sr,
        start_col = sc,
        end_row = er,
        end_col = ec,
      })
    end
  end

  return all_placeholders
end

local function is_java_brace_call(callee_text)
  local method = callee_text:match('([%w_]+)$')
  return method and java_brace_methods[method:lower()] or false
end

local function is_cpp_brace_call(callee_text)
  local lower = callee_text:lower()
  if lower:find('format', 1, true) ~= nil
    or lower:find('print', 1, true) ~= nil
    or lower:find('spdlog', 1, true) ~= nil then
    return true
  end
  local method = lower:match('([%w_]+)$')
  return method and (method == 'critical' or java_brace_methods[method]) or false
end

local function allow_percent_style(filetype, callee_text)
  local lower = callee_text:lower()

  if filetype == 'java' then
    return lower:find('printf', 1, true) ~= nil or lower:find('format', 1, true) ~= nil
  end

  if filetype == 'cpp' then
    return lower:find('format', 1, true) == nil and lower:find('spdlog', 1, true) == nil
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
      double_brace_escape = true,
    }
  end

  if filetype == 'java' and is_java_brace_call(callee_text) then
    return {
      allowed = true,
      empty_only = true,
      slash_escape = true,
      double_brace_escape = false,
    }
  end

  if filetype == 'cpp' and is_cpp_brace_call(callee_text) then
    return {
      allowed = true,
      empty_only = false,
      slash_escape = false,
      double_brace_escape = true,
    }
  end

  return { allowed = false }
end

local function is_error_call_candidate(node)
  if node:type() ~= 'ERROR' then
    return false
  end
  local paren_idx = correspondence.find_open_paren_index(node)
  if not paren_idx or paren_idx == 0 then
    return false
  end
  for i = 0, paren_idx - 1 do
    if node:child(i):named() then
      return true
    end
  end
  return false
end

local function get_call_argument_container(call_node)
  if call_node:type() == 'ERROR' then
    local paren_idx = correspondence.find_open_paren_index(call_node)
    if not paren_idx then
      return nil
    end
    local _, _, er, ec = call_node:range()
    local psr, psc = call_node:child(paren_idx):range()
    return call_node, { start_child_idx = paren_idx + 1, include_unnamed_tokens = false }, { psr, psc, er, ec }
  end

  for i = 0, call_node:named_child_count() - 1 do
    local child = call_node:named_child(i)
    local ctype = child:type()
    if arg_container_types[ctype] then
      local sr, sc, er, ec = child:range()
      return child, { start_child_idx = 0, include_unnamed_tokens = (ctype == 'token_tree') }, { sr, sc, er, ec }
    end
  end

  return nil
end

local function get_callee_text(call_node, container_range, bufnr)
  local call_sr, call_sc = call_node:range()
  local text = node_text(bufnr, call_sr, call_sc, container_range[1], container_range[2])
  return vim.trim(text)
end

local function resolve_format_call(bufnr, filetype, callee_text, slots, max_slot, has_comma)
  local lower_callee = callee_text:lower()
  local is_known_format = lower_callee:find('printf', 1, true) ~= nil
    or lower_callee:find('format', 1, true) ~= nil
    or lower_callee:find('log', 1, true) ~= nil

  for slot_idx = 0, max_slot do
    local entry = slots[slot_idx]
    if entry and entry.node then
      local segments = extract_format_segments(entry.node, bufnr)
      if segments then
        local is_valid_format_call = slot_idx < max_slot or has_comma or is_known_format
        if is_valid_format_call then
          local percent_opts = { filetype = filetype }
          if allow_percent_style(filetype, callee_text) then
            local placeholders = parse_format_placeholders(segments, parse_percent_placeholders, percent_opts)
            if #placeholders > 0 then
              return {
                format_slot = slot_idx,
                format_range = entry,
                placeholders = placeholders,
              }
            end
          end

          local brace_opts = brace_options(filetype, callee_text)
          if brace_opts.allowed then
            local placeholders = parse_format_placeholders(segments, parse_brace_placeholders, brace_opts)
            if #placeholders > 0 then
              return {
                format_slot = slot_idx,
                format_range = entry,
                placeholders = placeholders,
              }
            end
          end
        end
      end
    end
  end

  return nil
end

local function try_build_format_call(call_node, bufnr, filetype, crow, ccol, allow_trailing_ws)
  local arg_container, slot_opts, container_range = get_call_argument_container(call_node)
  if not arg_container or not container_range then
    return nil
  end

  local in_range = correspondence.is_pos_in_range(
    crow, ccol,
    container_range[1], container_range[2], container_range[3], container_range[4]
  )
  if not in_range then
    if not allow_trailing_ws or call_node:type() ~= 'ERROR' then
      return nil
    end
    local er, ec = container_range[3], container_range[4]
    if not correspondence.is_pos_at_or_after(crow, ccol, er, ec) then
      return nil
    end
    local between = node_text(bufnr, er, ec, crow, ccol + 1)
    if not between:match('^%s*$') then
      return nil
    end
    -- Verify the ERROR call is unclosed (no ')' after '(')
    local has_close = false
    for i = (slot_opts.start_child_idx or 0), call_node:child_count() - 1 do
      if call_node:child(i):type() == ')' then
        has_close = true
        break
      end
    end
    if has_close then
      return nil
    end
  end

  local callee_text = get_callee_text(call_node, container_range, bufnr)
  if callee_text == '' then
    return nil
  end

  local slots, max_slot = correspondence.get_slot_ranges(arg_container, slot_opts)
  local commas = correspondence.collect_top_level_commas(arg_container, slot_opts)
  local resolved = resolve_format_call(bufnr, filetype, callee_text, slots, max_slot, #commas > 0)
  if not resolved then
    return nil
  end

  return {
    arg_container = arg_container,
    slot_opts = slot_opts,
    slots = slots,
    resolved = resolved,
  }
end

local function find_enclosing_format_call(node, bufnr, filetype, crow, ccol)
  local valid_types = supported_filetypes[filetype]
  if not valid_types then
    return nil
  end

  local current = node
  while current do
    if valid_types[current:type()] or is_error_call_candidate(current) then
      local call_info = try_build_format_call(current, bufnr, filetype, crow, ccol, false)
      if call_info then
        return call_info
      end
    end
    current = current:parent()
  end

  -- Handle cursor on trailing whitespace/EOF after an unclosed ERROR call.
  local candidate_error
  for i = 0, node:child_count() - 1 do
    local child = node:child(i)
    local sr, sc = child:range()
    if correspondence.is_pos_at_or_after(crow, ccol, sr, sc) then
      if is_error_call_candidate(child) then
        candidate_error = child
      else
        candidate_error = nil
      end
    else
      break
    end
  end

  if candidate_error then
    return try_build_format_call(candidate_error, bufnr, filetype, crow, ccol, true)
  end

  return nil
end

local function resolve_cursor_match(bufnr)
  bufnr = (not bufnr or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  local filetype = vim.bo[bufnr].filetype
  if not supported_filetypes[filetype] then
    return nil
  end

  local node, crow, ccol = correspondence.get_node_at_cursor(bufnr)
  if not node then
    return nil
  end

  local call_info = find_enclosing_format_call(node, bufnr, filetype, crow, ccol)
  if not call_info then
    return nil
  end

  local resolved = call_info.resolved
  local slots = call_info.slots
  local format_slot = resolved.format_slot
  local format_range = resolved.format_range
  local placeholders = resolved.placeholders

  if correspondence.is_pos_in_range(
    crow, ccol,
    format_range.start_row, format_range.start_col,
    format_range.end_row, format_range.end_col
  ) then
    for _, placeholder in ipairs(placeholders) do
      if correspondence.is_pos_in_range(
        crow, ccol,
        placeholder.start_row, placeholder.start_col,
        placeholder.end_row, placeholder.end_col
      ) then
        local arg_range = slots[format_slot + placeholder.arg_index]
        return {
          placeholder_ranges = { placeholder },
          arg_range = arg_range,
          target_range = arg_range,
        }
      end
    end
    return nil
  end

  local cursor_slot = correspondence.get_slot_index(call_info.arg_container, crow, ccol, call_info.slot_opts)
  local arg_index = cursor_slot - format_slot
  if arg_index >= 1 then
    local matched_placeholders = {}
    for _, placeholder in ipairs(placeholders) do
      if placeholder.arg_index == arg_index then
        table.insert(matched_placeholders, placeholder)
      end
    end

    if #matched_placeholders > 0 then
      return {
        placeholder_ranges = matched_placeholders,
        arg_range = slots[cursor_slot],
        target_range = matched_placeholders[1],
      }
    end
  end

  return nil
end

function M.clear_highlights(bufnr)
  bufnr = (not bufnr or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  end
end

function M.update_highlights(bufnr)
  bufnr = (not bufnr or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  M.clear_highlights(bufnr)

  local match = resolve_cursor_match(bufnr)
  if not match then
    return
  end

  for _, p in ipairs(match.placeholder_ranges) do
    highlight_range(bufnr, p.start_row, p.start_col, p.end_row, p.end_col, 'PrintfPlaceholder')
  end

  local a = match.arg_range
  if a then
    highlight_range(bufnr, a.start_row, a.start_col, a.end_row, a.end_col, 'PrintfArgument')
  end
end

function M.get_corresponding_range(bufnr)
  local match = resolve_cursor_match(bufnr)
  if not match or not match.target_range then
    return nil
  end

  local t = match.target_range
  return t.start_row, t.start_col, t.end_row, t.end_col
end

function M.select_corresponding()
  local bufnr = vim.api.nvim_get_current_buf()
  local sr, sc, er, ec = M.get_corresponding_range(bufnr)
  return correspondence.select_range(bufnr, sr, sc, er, ec)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('PrintfHighlight', { clear = true })
  local filetypes = vim.tbl_keys(supported_filetypes)

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = filetypes,
    callback = function(args)
      local bufnr = args.buf
      if vim.b[bufnr]._printf_highlight_attached then
        return
      end
      vim.b[bufnr]._printf_highlight_attached = true

      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'TextChanged', 'TextChangedI' }, {
        group = group,
        buffer = bufnr,
        callback = function()
          M.update_highlights(bufnr)
        end,
      })
      vim.api.nvim_create_autocmd({ 'BufLeave' }, {
        group = group,
        buffer = bufnr,
        callback = function()
          M.clear_highlights(bufnr)
        end,
      })
      local jump_fn = function()
        M.select_corresponding()
      end

      for _, key in ipairs({ 'g=', 'gs', '<M-=>' }) do
        vim.keymap.set({ 'n', 'x' }, key, jump_fn, { buffer = bufnr, silent = true, desc = 'Jump and select corresponding printf placeholder/argument' })
      end
    end,
  })
end

return M
