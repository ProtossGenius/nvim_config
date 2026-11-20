local M = {}

local ns = vim.api.nvim_create_namespace("sql_insert_highlight")
local hl_group = "SqlInsertMatch"

local IGNORED_LIST_CHILD_TYPES = {
  comment = true,
  marginalia = true,
  ERROR = true,
}

local function is_pos_at_or_after(row, col, ref_row, ref_col)
  return row > ref_row or (row == ref_row and col >= ref_col)
end

local function collect_commas_from_node(node, commas)
  for i = 0, node:child_count() - 1 do
    local child = node:child(i)
    local ctype = child:type()
    if ctype == ',' then
      local _, _, er, ec = child:range()
      table.insert(commas, { end_row = er, end_col = ec })
    elseif ctype == 'ERROR' then
      collect_commas_from_node(child, commas)
    end
  end
end

local function collect_top_level_commas(list_node)
  local commas = {}
  collect_commas_from_node(list_node, commas)
  return commas
end

local function get_list_slot_index(list_node, crow, ccol)
  local commas = collect_top_level_commas(list_node)
  local slot = 0
  for _, comma in ipairs(commas) do
    if is_pos_at_or_after(crow, ccol, comma.end_row, comma.end_col) then
      slot = slot + 1
    end
  end
  return slot
end

local function get_list_slots(list_node)
  local slots = {}
  local slot = 0
  for i = 0, list_node:child_count() - 1 do
    local child = list_node:child(i)
    local ctype = child:type()
    if ctype == ',' then
      slot = slot + 1
    elseif ctype == 'ERROR' then
      slot = slot + #collect_top_level_commas(child)
    elseif child:named() and not IGNORED_LIST_CHILD_TYPES[ctype] and not child:missing() then
      local sr, sc, er, ec = child:range()
      if not (sr == er and sc == ec) then
        slots[slot] = child
      end
    end
  end
  return slots
end

function M.get_corresponding_range(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then return end
  parser:parse()

  local node = vim.treesitter.get_node()
  if not node then return end

  -- Traverse up to find a list node that is a child of an insert node
  local list_node = node
  while list_node do
    if list_node:type() == 'list' then
      local parent = list_node:parent()
      if parent and parent:type() == 'insert' then
        break
      end
    end
    list_node = list_node:parent()
  end

  if not list_node then return end
  local insert_node = list_node:parent()

  local column_list
  local value_lists = {}
  local seen_values = false
  for i = 0, insert_node:named_child_count() - 1 do
    local child = insert_node:named_child(i)
    local ctype = child:type()
    if ctype == 'keyword_values' then
      seen_values = true
    elseif ctype == 'list' then
      if seen_values then
        table.insert(value_lists, child)
      elseif not column_list then
        column_list = child
      end
    end
  end

  if not column_list or #value_lists == 0 then
    return nil
  end

  local current_list, other_list
  if list_node == column_list then
    current_list = column_list
    other_list = value_lists[1]
  else
    for _, value_list in ipairs(value_lists) do
      if list_node == value_list then
        current_list = value_list
        other_list = column_list
        break
      end
    end
  end

  if not current_list then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local crow = cursor[1] - 1
  local ccol = cursor[2]

  local index = get_list_slot_index(current_list, crow, ccol)
  local slots = get_list_slots(other_list)
  local corresponding = slots[index]
  if corresponding then
    return corresponding:range()
  end

  return nil
end

function M.highlight_corresponding()
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local sr, sc, er, ec = M.get_corresponding_range(bufnr)
  if sr then
    vim.api.nvim_buf_set_extmark(bufnr, ns, sr, sc, {
      end_row = er,
      end_col = ec,
      hl_group = hl_group,
      hl_mode = "combine",
      priority = 300,
    })
  end
end

function M.select_corresponding()
  local bufnr = vim.api.nvim_get_current_buf()
  local mode = vim.api.nvim_get_mode().mode
  if mode:find("[vV\22]") then
    vim.cmd("normal! \27")
  end

  local sr, sc, er, ec = M.get_corresponding_range(bufnr)
  if not sr then
    return false
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
    local prev_line = vim.api.nvim_buf_get_lines(bufnr, end_row - 1, end_row, false)[1] or ""
    end_col = math.max(0, #prev_line - 1)
  end

  vim.api.nvim_win_set_cursor(0, { start_row, start_col })
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(0, { end_row, end_col })
  return true
end

function M.setup()
  -- Define a bold underline highlight that is always visible on any colorscheme
  vim.api.nvim_set_hl(0, hl_group, { underline = true, bold = true, bg = "#504945" })

  -- Re-apply after colorscheme changes
  vim.api.nvim_create_autocmd("ColorScheme", {
    callback = function()
      vim.api.nvim_set_hl(0, hl_group, { underline = true, bold = true, bg = "#504945" })
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "sql",
    callback = function(args)
      local bufnr = args.buf
      -- Avoid attaching twice to the same buffer
      if vim.b[bufnr]._sql_highlight_attached then return end
      vim.b[bufnr]._sql_highlight_attached = true

      vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        buffer = bufnr,
        callback = function()
          M.highlight_corresponding()
        end,
      })

      local jump_fn = function()
        M.select_corresponding()
      end

      for _, key in ipairs({ 'g=', 'gs', '<M-=>' }) do
        vim.keymap.set({ 'n', 'x' }, key, jump_fn, { buffer = bufnr, silent = true, desc = 'Jump and select corresponding SQL field/value' })
      end
    end,
  })
end

return M
