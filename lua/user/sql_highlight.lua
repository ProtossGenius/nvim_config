local correspondence = require('user.correspondence')

local M = {}

local ns = vim.api.nvim_create_namespace("sql_insert_highlight")
local hl_group = "SqlInsertMatch"
local last_value_idx_by_buf = {}

local function find_insert_container(node)
  local current = node
  while current do
    local ctype = current:type()
    local parent = current:parent()
    if ctype == 'list' and parent and parent:type() == 'insert' then
      return current, parent
    elseif ctype == 'select_expression' and parent and parent:type() == 'select' then
      local grandparent = parent:parent()
      if grandparent and grandparent:type() == 'insert' then
        return current, grandparent
      end
    end
    current = parent
  end
  return nil, nil
end

local function collect_insert_containers(insert_node)
  local column_list
  local value_containers = {}
  local seen_values = false

  for i = 0, insert_node:named_child_count() - 1 do
    local child = insert_node:named_child(i)
    local ctype = child:type()
    if ctype == 'keyword_values' then
      seen_values = true
    elseif ctype == 'list' then
      if seen_values then
        table.insert(value_containers, child)
      elseif not column_list then
        column_list = child
      end
    elseif ctype == 'select' and column_list then
      for j = 0, child:named_child_count() - 1 do
        local sub = child:named_child(j)
        if sub:type() == 'select_expression' then
          table.insert(value_containers, sub)
        end
      end
    end
  end

  return column_list, value_containers
end

local function node_range_key(node)
  local sr, sc, er, ec = node:range()
  return string.format("%d:%d:%d:%d", sr, sc, er, ec)
end

function M.clear_highlights(bufnr)
  bufnr = (not bufnr or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

local function resolve_correspondence(bufnr)
  bufnr = (not bufnr or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr

  local node, crow, ccol = correspondence.get_node_at_cursor(bufnr)
  if not node then
    return nil
  end

  local container_node, insert_node = find_insert_container(node)
  if not container_node or not insert_node then
    return nil
  end

  local column_list, value_containers = collect_insert_containers(insert_node)
  if not column_list or #value_containers == 0 then
    return nil
  end

  local insert_key = node_range_key(insert_node)
  local current_container, other_container, from_value_idx

  if container_node == column_list then
    local target_idx = 1
    local saved = last_value_idx_by_buf[bufnr]
    if saved and saved.insert_key == insert_key and saved.index >= 1 and saved.index <= #value_containers then
      target_idx = saved.index
    end
    current_container = column_list
    other_container = value_containers[target_idx]
  else
    for idx, value_container in ipairs(value_containers) do
      if container_node == value_container then
        from_value_idx = idx
        current_container = value_container
        other_container = column_list
        break
      end
    end
  end

  if not current_container or not other_container then
    return nil
  end

  local index = correspondence.get_slot_index(current_container, crow, ccol)
  local slots = correspondence.get_slot_ranges(other_container)
  local target = slots[index]
  if not target then
    return nil
  end

  return {
    target = target,
    insert_key = insert_key,
    from_value_idx = from_value_idx,
  }
end

function M.get_corresponding_range(bufnr)
  local res = resolve_correspondence(bufnr)
  if not res then
    return nil
  end

  local t = res.target
  return t.start_row, t.start_col, t.end_row, t.end_col
end

function M.highlight_corresponding(bufnr)
  bufnr = (not bufnr or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  M.clear_highlights(bufnr)

  local res = resolve_correspondence(bufnr)
  if not res then
    last_value_idx_by_buf[bufnr] = nil
    return
  end

  local t = res.target
  vim.api.nvim_buf_set_extmark(bufnr, ns, t.start_row, t.start_col, {
    end_row = t.end_row,
    end_col = t.end_col,
    hl_group = hl_group,
    hl_mode = "combine",
    priority = 300,
  })
end

function M.select_corresponding()
  local bufnr = vim.api.nvim_get_current_buf()
  local res = resolve_correspondence(bufnr)
  if not res then
    return false
  end

  local t = res.target
  local selected = correspondence.select_range(bufnr, t.start_row, t.start_col, t.end_row, t.end_col)
  if selected then
    if res.from_value_idx then
      last_value_idx_by_buf[bufnr] = {
        insert_key = res.insert_key,
        index = res.from_value_idx,
      }
    else
      last_value_idx_by_buf[bufnr] = nil
    end
  end

  return selected
end

function M.setup()
  local group = vim.api.nvim_create_augroup("SqlInsertHighlight", { clear = true })

  -- Define a bold underline highlight that is always visible on any colorscheme
  vim.api.nvim_set_hl(0, hl_group, { underline = true, bold = true, bg = "#504945" })

  -- Re-apply after colorscheme changes
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      vim.api.nvim_set_hl(0, hl_group, { underline = true, bold = true, bg = "#504945" })
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "sql",
    callback = function(args)
      local bufnr = args.buf
      -- Avoid attaching twice to the same buffer
      if vim.b[bufnr]._sql_highlight_attached then return end
      vim.b[bufnr]._sql_highlight_attached = true

      vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI" }, {
        group = group,
        buffer = bufnr,
        callback = function()
          M.highlight_corresponding(bufnr)
        end,
      })

      vim.api.nvim_create_autocmd("BufLeave", {
        group = group,
        buffer = bufnr,
        callback = function()
          M.clear_highlights(bufnr)
        end,
      })

      vim.api.nvim_create_autocmd("BufWipeout", {
        group = group,
        buffer = bufnr,
        callback = function()
          last_value_idx_by_buf[bufnr] = nil
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
