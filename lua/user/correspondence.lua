-- [[ user.correspondence ]]
-- Shared tree-sitter comma-slot and visual-selection helpers for SQL/printf correspondence.

local M = {}

local IGNORED_CHILD_TYPES = {
  comment = true,
  line_comment = true,
  block_comment = true,
  marginalia = true,
  ERROR = true,
}

local DELIMITER_TYPES = {
  ['('] = true,
  [')'] = true,
  ['['] = true,
  [']'] = true,
  ['{'] = true,
  ['}'] = true,
  [','] = true,
  comma = true,
}

--- Return true when (row, col) is at or after (ref_row, ref_col).
function M.is_pos_at_or_after(row, col, ref_row, ref_col)
  return row > ref_row or (row == ref_row and col >= ref_col)
end

--- Return true when (row, col) lies in the half-open range [start, end).
function M.is_pos_in_range(row, col, sr, sc, er, ec)
  if row < sr or row > er then
    return false
  end
  if row == sr and col < sc then
    return false
  end
  if row == er and col >= ec then
    return false
  end
  return true
end

--- Find the 0-based child index of the first direct '(' token inside node.
function M.find_open_paren_index(node)
  for i = 0, node:child_count() - 1 do
    if node:child(i):type() == '(' then
      return i
    end
  end
  return nil
end

local function collect_commas_from_node(node, start_idx, commas)
  for i = start_idx, node:child_count() - 1 do
    local child = node:child(i)
    local ctype = child:type()
    if ctype == ',' or ctype == 'comma' then
      local sr, sc, er, ec = child:range()
      table.insert(commas, {
        start_row = sr,
        start_col = sc,
        end_row = er,
        end_col = ec,
      })
    elseif ctype == 'ERROR' then
      -- Only descend into ERROR wrappers; never into nested expression/array/call containers.
      collect_commas_from_node(child, 0, commas)
    end
  end
end

--- Collect all top-level comma tokens directly inside container (or wrapped in ERROR).
---@param container TSNode
---@param opts? { start_child_idx?: integer }
function M.collect_top_level_commas(container, opts)
  opts = opts or {}
  local commas = {}
  collect_commas_from_node(container, opts.start_child_idx or 0, commas)
  return commas
end

--- Compute the 0-based slot index for (row, col) inside a comma-separated container.
--- Cursor on a comma itself stays in the slot before the comma; cursor at or after
--- comma end belongs to the slot after the comma.
function M.get_slot_index(container, row, col, opts)
  local commas = M.collect_top_level_commas(container, opts)
  local slot = 0
  for _, comma in ipairs(commas) do
    if M.is_pos_at_or_after(row, col, comma.end_row, comma.end_col) then
      slot = slot + 1
    end
  end
  return slot
end

--- Build a 0-based map of slot -> range metadata for a comma-separated container.
---@param container TSNode
---@param opts? { start_child_idx?: integer, include_unnamed_tokens?: boolean }
function M.get_slot_ranges(container, opts)
  opts = opts or {}
  local start_idx = opts.start_child_idx or 0
  local include_unnamed = opts.include_unnamed_tokens == true
  local slots = {}
  local slot = 0

  for i = start_idx, container:child_count() - 1 do
    local child = container:child(i)
    local ctype = child:type()
    if ctype == ',' or ctype == 'comma' then
      slot = slot + 1
    elseif ctype == 'ERROR' then
      slot = slot + #M.collect_top_level_commas(child)
    elseif not IGNORED_CHILD_TYPES[ctype]
      and not DELIMITER_TYPES[ctype]
      and (include_unnamed or child:named())
      and not child:missing() then
      local sr, sc, er, ec = child:range()
      if not (sr == er and sc == ec) then
        local entry = slots[slot]
        if not entry then
          slots[slot] = {
            start_row = sr,
            start_col = sc,
            end_row = er,
            end_col = ec,
            node = child,
            token_count = 1,
          }
        else
          entry.end_row = er
          entry.end_col = ec
          entry.node = nil
          entry.token_count = entry.token_count + 1
        end
      end
    end
  end

  return slots, slot
end

--- Reparse the buffer's treesitter tree and return the node and 0-based cursor position.
function M.get_node_at_cursor(bufnr)
  bufnr = (not bufnr or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) or bufnr ~= vim.api.nvim_get_current_buf() then
    return nil, 0, 0
  end

  pcall(function()
    local parser = vim.treesitter.get_parser(bufnr)
    if parser then
      parser:parse()
    end
  end)

  local cursor = vim.api.nvim_win_get_cursor(0)
  local crow = cursor[1] - 1
  local ccol = cursor[2]

  local node
  if vim.treesitter.get_node then
    local ok, ts_node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { crow, ccol } })
    if ok then
      node = ts_node
    end
  end

  if not node then
    local ok, ts_utils = pcall(require, 'nvim-treesitter.ts_utils')
    if ok then
      node = ts_utils.get_node_at_cursor()
    end
  end

  return node, crow, ccol
end

--- Visually select the half-open byte range [sr:sc, er:ec) without clobbering mode on empty range.
function M.select_range(bufnr, sr, sc, er, ec)
  if not sr or (sr == er and sc == ec) then
    return false
  end

  bufnr = (not bufnr or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  local mode = vim.api.nvim_get_mode().mode
  if mode:find('[vV\22]') then
    vim.cmd('normal! \27')
  end

  local start_row = sr + 1
  local start_col = sc
  local end_row = er + 1
  local end_col

  if sr == er then
    end_col = math.max(sc, ec - 1)
  elseif ec > 0 then
    end_col = ec - 1
  else
    end_row = math.max(start_row, er)
    local prev_line = vim.api.nvim_buf_get_lines(bufnr, end_row - 1, end_row, false)[1] or ''
    end_col = math.max(0, #prev_line - 1)
  end

  vim.api.nvim_win_set_cursor(0, { start_row, start_col })
  vim.cmd('normal! v')
  vim.api.nvim_win_set_cursor(0, { end_row, end_col })
  return true
end

return M
