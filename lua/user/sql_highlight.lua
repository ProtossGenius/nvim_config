local M = {}

local ns = vim.api.nvim_create_namespace("sql_insert_highlight")
local hl_group = "SqlInsertMatch"

function M.get_corresponding_range(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then return end
  parser:parse()

  local node = vim.treesitter.get_node()
  if not node then return end

  -- Traverse up to find a list node that is a child of an insert node
  local target_node = node
  local list_node = node
  while list_node do
    if list_node:type() == 'list' then
      local parent = list_node:parent()
      if parent and parent:type() == 'insert' then
        break
      end
    end
    target_node = list_node
    list_node = list_node:parent()
  end

  if not list_node then return end
  local insert_node = list_node:parent()

  local lists = {}
  for i = 0, insert_node:named_child_count() - 1 do
    if insert_node:named_child(i):type() == 'list' then
      table.insert(lists, insert_node:named_child(i))
    end
  end

  if #lists == 2 then
    local current_list, other_list
    if lists[1] == list_node then
      current_list = lists[1]
      other_list = lists[2]
    elseif lists[2] == list_node then
      current_list = lists[2]
      other_list = lists[1]
    end

    if current_list then
      local index = -1
      for i = 0, current_list:named_child_count() - 1 do
        if current_list:named_child(i) == target_node then
          index = i
          break
        end
      end

      if index == -1 then
        local cursor = vim.api.nvim_win_get_cursor(0)
        local crow = cursor[1] - 1
        local ccol = cursor[2]

        for i = 0, current_list:named_child_count() - 1 do
          local child = current_list:named_child(i)
          local sr, sc, er, ec = child:range()
          if crow == sr and crow == er then
            if ccol >= sc and ccol < ec then
              index = i
              break
            end
          elseif (crow > sr or (crow == sr and ccol >= sc))
            and (crow < er or (crow == er and ccol < ec)) then
            index = i
            break
          end
        end

        if index == -1 then
          for i = current_list:named_child_count() - 1, 0, -1 do
            local child = current_list:named_child(i)
            local sr, sc = child:range()
            if crow > sr or (crow == sr and ccol >= sc) then
              index = i
              break
            end
          end
        end

        if index == -1 and current_list:named_child_count() > 0 then
          index = 0
        end
      end

      if index >= 0 and index < other_list:named_child_count() then
        local corresponding = other_list:named_child(index)
        return corresponding:range()
      end
    end
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
  local end_col = math.max(sc, ec - 1)

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
