local M = {}

local visual_modes = {
  v = true,
  V = true,
  ['\022'] = true,
}

local function is_visual_mode(mode)
  return visual_modes[mode] == true
end

function M.get_visual_selection()
  local mode = vim.api.nvim_get_mode().mode
  if not is_visual_mode(mode) then
    return nil
  end

  if mode == '\022' then
    vim.notify('Blockwise visual mode is not supported.', vim.log.levels.WARN)
    return nil
  end

  local start_pos = vim.fn.getpos('v')
  local end_pos = vim.fn.getcurpos()
  local lines = vim.fn.getregion(start_pos, end_pos, { type = mode })
  local text = table.concat(lines, '\n')
  if vim.trim(text) == '' then
    return nil
  end

  return text
end

function M.get_buffer_text(bufnr)
  bufnr = bufnr or 0
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
end

function M.get_extension(bufnr)
  bufnr = bufnr or 0
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    return ''
  end

  return string.lower(vim.fn.fnamemodify(name, ':e'))
end

function M.get_fence_language(bufnr)
  bufnr = bufnr or 0
  local filetype = vim.bo[bufnr].filetype
  if filetype ~= '' then
    return filetype
  end

  return M.get_extension(bufnr)
end

function M.split_lines(text)
  if text == '' then
    return { '' }
  end

  return vim.split(text, '\n', { plain = true })
end

function M.append_code_block(lines, label, filetype, text)
  if not text or vim.trim(text) == '' then
    return
  end

  if label and label ~= '' then
    table.insert(lines, label)
  end

  table.insert(lines, string.format('```%s', filetype or ''))
  vim.list_extend(lines, M.split_lines(text))
  table.insert(lines, '```')
end

return M
