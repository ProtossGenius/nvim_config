local M = {}

local results = {}

function M.expect_equal(name, actual, expected)
  if not vim.deep_equal(actual, expected) then
    error(string.format('%s failed\nexpected: %s\nactual:   %s', name, vim.inspect(expected), vim.inspect(actual)))
  end

  table.insert(results, 'PASS ' .. name)
end

function M.expect_true(name, value)
  if not value then
    error(name .. ' failed\nexpected: true\nactual:   ' .. vim.inspect(value))
  end

  table.insert(results, 'PASS ' .. name)
end

function M.reset(lines, filetype, lang)
  vim.cmd('enew!')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.cmd('setlocal buftype=')
  vim.cmd('setlocal bufhidden=wipe')
  vim.cmd('setlocal noswapfile')
  vim.cmd('setlocal modifiable')
  vim.bo.readonly = false
  vim.cmd('setfiletype ' .. filetype)

  if lang then
    local ok, parser = pcall(vim.treesitter.get_parser, 0, lang)
    if ok and parser then
      pcall(function() parser:parse(true) end)
    else
      pcall(vim.treesitter.start, 0, lang)
      local started, started_parser = pcall(vim.treesitter.get_parser, 0, lang)
      if started and started_parser then
        pcall(function() started_parser:parse(true) end)
      end
    end
  end

  vim.wait(80)
end

function M.feed(keys)
  local termcodes = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(termcodes, 'xt', false)
  vim.wait(80)
end

function M.current_lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

function M.find_substring(text, needle, occurrence)
  occurrence = occurrence or 1
  local from = 1

  for _ = 1, occurrence do
    local start_col, end_col = text:find(needle, from, true)
    if not start_col then
      error(string.format('Could not find substring %q in %q', needle, text))
    end
    if occurrence == 1 then
      return start_col, end_col
    end
    occurrence = occurrence - 1
    from = end_col + 1
  end
end

function M.set_cursor_on_substring(line_nr, needle, occurrence, byte_offset)
  local line = vim.api.nvim_buf_get_lines(0, line_nr - 1, line_nr, false)[1]
  local start_col = M.find_substring(line, needle, occurrence)
  vim.api.nvim_win_set_cursor(0, { line_nr, start_col - 1 + (byte_offset or 0) })
  vim.wait(50)
end

function M.get_highlights(ns)
  local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
  local highlights = {}

  for _, mark in ipairs(marks) do
    local details = mark[4] or {}
    table.insert(highlights, {
      row = mark[2],
      col = mark[3],
      end_row = details.end_row or mark[2],
      end_col = details.end_col,
      hl_group = details.hl_group,
    })
  end

  table.sort(highlights, function(left, right)
    if left.row ~= right.row then
      return left.row < right.row
    end
    if left.col ~= right.col then
      return left.col < right.col
    end
    return (left.hl_group or '') < (right.hl_group or '')
  end)

  return highlights
end

function M.flush()
  for _, result in ipairs(results) do
    print(result)
  end
end

return M
