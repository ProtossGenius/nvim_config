local M = {}

local esc = vim.api.nvim_replace_termcodes('<ESC>', true, false, true)
local visual_block_mode = '\22'

local function get_comment_ft()
  return require('Comment.ft')
end

local function get_comment_utils()
  return require('Comment.utils')
end

local function refresh_treesitter()
  local ok, parser = pcall(vim.treesitter.get_parser, 0)
  if ok then
    parser:parse(true)
  end
end

local function split_commentstring(commentstring)
  if type(commentstring) ~= 'string' or commentstring == '' then
    return nil, nil
  end

  local left, right = commentstring:match('^(.*)%%s(.*)$')
  if not left then
    return nil, nil
  end

  return vim.trim(left), vim.trim(right)
end

local function get_commentstring(lang, ctype)
  return get_comment_ft().get(lang, ctype)
end

local function supports_block_comment(visual_mode)
  local comment_ft = get_comment_ft()
  local comment_utils = get_comment_utils()
  local commentstring = comment_ft.calculate({
    ctype = comment_utils.ctype.blockwise,
    range = comment_utils.get_region(visual_mode),
  })

  return type(commentstring) == 'string' and commentstring:match('%%s') ~= nil
end

local function in_visual_mode()
  local mode = vim.api.nvim_get_mode().mode
  return mode == 'v' or mode == 'V' or mode == visual_block_mode
end

local function start_visual_selection(selection_mode, start_pos, end_pos)
  if in_visual_mode() then
    vim.api.nvim_feedkeys(esc, 'nx', false)
  end

  vim.api.nvim_win_set_cursor(0, { start_pos[2], math.max(0, start_pos[3] - 1) })

  if selection_mode == 'V' then
    vim.cmd('normal! V')
    vim.api.nvim_win_set_cursor(0, { end_pos[2], 0 })
    return
  end

  vim.cmd('normal! v')
  vim.api.nvim_win_set_cursor(0, { end_pos[2], math.max(0, end_pos[3] - 1) })
end

local function get_embedded_comment_node()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local ok, node = pcall(vim.treesitter.get_node, {
    bufnr = 0,
    pos = { cursor[1] - 1, cursor[2] },
    ignore_injections = false,
  })

  if not ok or not node then
    return nil, nil
  end

  while node and node:type() ~= 'comment' do
    node = node:parent()
  end

  if not node then
    return nil, nil
  end

  local parser_ok, parser = pcall(vim.treesitter.get_parser, 0)
  if not parser_ok then
    return nil, nil
  end

  local srow, scol, erow, ecol = node:range()
  local lang_tree = get_comment_ft().contains(parser, {
    srow,
    scol,
    erow,
    math.max(scol, ecol - 1),
  })

  if not lang_tree then
    return nil, nil
  end

  local lang = lang_tree:lang()
  if lang == vim.bo.filetype then
    return nil, nil
  end

  return node, lang
end

local function build_charwise_selection(srow, scol, erow, ecol)
  if erow < srow or (erow == srow and ecol <= scol) then
    return nil
  end

  return {
    'v',
    { 0, srow + 1, scol + 1, 0 },
    { 0, erow + 1, ecol, 0 },
  }
end

local function build_linewise_selection(srow, erow)
  return {
    'V',
    { 0, srow + 1, 1, 0 },
    { 0, erow + 1, 1, 0 },
  }
end

local function full_line_comment(node)
  local srow, scol, erow, ecol = node:range()
  if srow ~= erow then
    return false
  end

  local line = vim.api.nvim_buf_get_lines(0, srow, srow + 1, false)[1] or ''
  return vim.trim(line:sub(1, scol)) == '' and ecol >= #line
end

local function get_node_text(node)
  local text = vim.treesitter.get_node_text(node, 0)
  if type(text) == 'table' then
    return table.concat(text, '\n')
  end

  return text or ''
end

local function trim_inner_line_comment(node, left)
  local srow, scol, erow, ecol = node:range()
  local line = vim.api.nvim_buf_get_lines(0, srow, srow + 1, false)[1] or ''
  local start_col = scol + #left
  local end_col = ecol

  if line:sub(start_col + 1, start_col + 1) == ' ' then
    start_col = start_col + 1
  end

  while end_col > start_col and line:sub(end_col, end_col):match('%s') do
    end_col = end_col - 1
  end

  return build_charwise_selection(srow, start_col, erow, end_col)
end

local function trim_inner_block_comment(node, left, right)
  local srow, scol, erow, ecol = node:range()
  local first_line = vim.api.nvim_buf_get_lines(0, srow, srow + 1, false)[1] or ''
  local last_line = vim.api.nvim_buf_get_lines(0, erow, erow + 1, false)[1] or ''
  local start_col = scol + #left
  local end_col = ecol - #right

  if first_line:sub(start_col + 1, start_col + 1) == ' ' then
    start_col = start_col + 1
  end

  if end_col > 0 and last_line:sub(end_col, end_col) == ' ' then
    end_col = end_col - 1
  end

  return build_charwise_selection(srow, start_col, erow, end_col)
end

local function get_embedded_textobj_selection(inside)
  local node, lang = get_embedded_comment_node()
  if not node or not lang then
    return nil
  end

  local text = get_node_text(node)
  local comment_utils = get_comment_utils()
  local line_left = split_commentstring(get_commentstring(lang, comment_utils.ctype.linewise))
  local block_left, block_right = split_commentstring(get_commentstring(lang, comment_utils.ctype.blockwise))

  if block_left and block_right and block_right ~= '' and vim.startswith(text, block_left) and vim.endswith(text, block_right) then
    if inside then
      return trim_inner_block_comment(node, block_left, block_right)
    end

    local srow, scol, erow, ecol = node:range()
    return build_charwise_selection(srow, scol, erow, ecol)
  end

  if line_left and vim.startswith(text, line_left) then
    if inside then
      return trim_inner_line_comment(node, line_left)
    end

    if full_line_comment(node) then
      local srow, _, erow, _ = node:range()
      return build_linewise_selection(srow, erow)
    end

    local srow, scol, erow, ecol = node:range()
    return build_charwise_selection(srow, scol, erow, ecol)
  end

  return nil
end

local function get_default_textobj_selection(inside)
  local fn_name = inside and 'textobj#comment#select_i' or 'textobj#comment#select_a'
  local result = vim.fn[fn_name]()

  if result == 0 or vim.tbl_isempty(result) then
    return nil
  end

  return result
end

function M.commentstring_pre_hook(ctx)
  refresh_treesitter()
  return get_comment_ft().calculate(ctx)
end

function M.toggle_current()
  refresh_treesitter()
  require('Comment.api').toggle.linewise.current()
end

function M.toggle_visual(visual_mode)
  visual_mode = visual_mode or vim.fn.visualmode()

  refresh_treesitter()

  local comment_type
  if visual_mode == 'V' or visual_mode == visual_block_mode then
    comment_type = 'linewise'
  else
    comment_type = supports_block_comment(visual_mode) and 'blockwise' or 'linewise'
  end

  if in_visual_mode() then
    vim.api.nvim_feedkeys(esc, 'nx', false)
  end

  require('Comment.api').toggle[comment_type](visual_mode)
end

function M.select_comment(inside)
  refresh_treesitter()

  local selection = get_embedded_textobj_selection(inside) or get_default_textobj_selection(inside)
  if not selection then
    return
  end

  start_visual_selection(selection[1], selection[2], selection[3])
end

function M.select_around()
  M.select_comment(false)
end

function M.select_inner()
  M.select_comment(true)
end

return M
