-- [[ user.translate ]]
-- Context-aware translation via local LLM providers.

local client = require('user.llm.client')
local config = require('user.llm.config')
local context = require('user.llm.context')

local M = {}

local state = {
  buf = nil,
  win = nil,
}

local comment_styles = {
  c = { line = '//', block_start = '/*', block_end = '*/' },
  cc = { line = '//', block_start = '/*', block_end = '*/' },
  cpp = { line = '//', block_start = '/*', block_end = '*/' },
  cxx = { line = '//', block_start = '/*', block_end = '*/' },
  h = { line = '//', block_start = '/*', block_end = '*/' },
  hpp = { line = '//', block_start = '/*', block_end = '*/' },
  hxx = { line = '//', block_start = '/*', block_end = '*/' },
  java = { line = '//', block_start = '/*', block_end = '*/' },
  js = { line = '//', block_start = '/*', block_end = '*/' },
  jsx = { line = '//', block_start = '/*', block_end = '*/' },
  ts = { line = '//', block_start = '/*', block_end = '*/' },
  tsx = { line = '//', block_start = '/*', block_end = '*/' },
  go = { line = '//', block_start = '/*', block_end = '*/' },
  rs = { line = '//', block_start = '/*', block_end = '*/' },
  swift = { line = '//', block_start = '/*', block_end = '*/' },
  kt = { line = '//', block_start = '/*', block_end = '*/' },
  kts = { line = '//', block_start = '/*', block_end = '*/' },
  css = { block_start = '/*', block_end = '*/' },
  scss = { block_start = '/*', block_end = '*/' },
  sql = { line = '--', block_start = '/*', block_end = '*/' },
  lua = { line = '--', block_start = '--[[', block_end = ']]' },
  py = { line = '#' },
  rb = { line = '#' },
  sh = { line = '#' },
  zsh = { line = '#' },
  fish = { line = '#' },
  yaml = { line = '#' },
  yml = { line = '#' },
  toml = { line = '#' },
  conf = { line = '#' },
  ini = { line = ';' },
  vim = { line = '"' },
  tex = { line = '%' },
}

local function get_model_ref()
  return config.models.translate
end

local function contains_han(text)
  for _, char in ipairs(vim.fn.split(text, '\\zs')) do
    local codepoint = vim.fn.char2nr(char)
    if codepoint >= 0x3400 and codepoint <= 0x9FFF then
      return true
    end
  end

  return false
end

local function resolve_language_pair(text)
  if contains_han(text) then
    return {
      source_lang = 'Chinese (Simplified)',
      source_code = 'zh-Hans',
      target_lang = 'English',
      target_code = 'en',
    }
  end

  return {
    source_lang = 'English',
    source_code = 'en',
    target_lang = 'Chinese (Simplified)',
    target_code = 'zh-Hans',
  }
end

local function build_prompt(text, pair)
  return table.concat({
    string.format(
      'You are a professional %s (%s) to %s (%s) translator. Your goal is to accurately convey the meaning and nuances of the original %s text while adhering to %s grammar, vocabulary, and cultural sensitivities.',
      pair.source_lang,
      pair.source_code,
      pair.target_lang,
      pair.target_code,
      pair.source_lang,
      pair.target_lang
    ),
    string.format(
      'Produce only the %s translation, without any additional explanations or commentary. Please translate the following %s text into %s:',
      pair.target_lang,
      pair.source_lang,
      pair.target_lang
    ),
    '',
    text,
  }, '\n')
end

local function close_float()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end

  state.win = nil
  state.buf = nil
end

local function calculate_width(lines)
  local max_width = 0

  for _, line in ipairs(lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
  end

  local min_width = 40
  local max_allowed = math.max(min_width, math.floor(vim.o.columns * 0.75))
  return math.min(math.max(max_width + 4, min_width), max_allowed)
end

local function calculate_height(lines)
  local min_height = 4
  local max_allowed = math.max(min_height, math.floor(vim.o.lines * 0.6))
  return math.min(math.max(#lines + 2, min_height), max_allowed)
end

local function render_float(content_lines, title)
  close_float()

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].bufhidden = 'wipe'
  vim.bo[state.buf].buftype = 'nofile'
  vim.bo[state.buf].filetype = 'markdown'
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, content_lines)
  vim.bo[state.buf].modifiable = false

  local width = calculate_width(content_lines)
  local height = calculate_height(content_lines)
  local row = math.floor((vim.o.lines - height) / 2) - 1
  local col = math.floor((vim.o.columns - width) / 2)

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = 'editor',
    style = 'minimal',
    border = 'rounded',
    title = title,
    title_pos = 'center',
    row = math.max(row, 0),
    col = math.max(col, 0),
    width = width,
    height = height,
  })

  vim.wo[state.win].wrap = true
  vim.wo[state.win].linebreak = true
  vim.wo[state.win].cursorline = false
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = 'no'
  vim.wo[state.win].winhighlight = 'NormalFloat:NormalFloat,FloatBorder:FloatBorder'

  for _, lhs in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', lhs, close_float, { buffer = state.buf, silent = true, nowait = true })
  end
end

local function show_error(message)
  render_float(vim.split(message, '\n', { plain = true }), ' LLM Translation Error ')
end

local function collapse_text(parts)
  local merged = {}
  for _, part in ipairs(parts) do
    local cleaned = vim.trim(part)
    if cleaned ~= '' then
      table.insert(merged, cleaned)
    end
  end

  return vim.trim(table.concat(merged, ' '):gsub('%s+', ' '))
end

local function get_comment_style(bufnr)
  local extension = context.get_extension(bufnr)
  if extension ~= '' and comment_styles[extension] then
    return comment_styles[extension]
  end

  return comment_styles[vim.bo[bufnr].filetype]
end

local function line_starts_with_comment(line, marker)
  if not marker then
    return false
  end

  return vim.startswith(vim.trim(line), marker)
end

local function strip_leading_comment(line, marker)
  local trimmed = vim.trim(line)
  if not marker or not vim.startswith(trimmed, marker) then
    return line
  end

  return vim.trim(trimmed:sub(#marker + 1))
end

local function extract_multiline_line_comment(bufnr, cursor_lnum, marker)
  if not marker then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local current = lines[cursor_lnum]
  if not current or not line_starts_with_comment(current, marker) then
    return nil
  end

  local start_lnum = cursor_lnum
  while start_lnum > 1 and line_starts_with_comment(lines[start_lnum - 1], marker) do
    start_lnum = start_lnum - 1
  end

  local end_lnum = cursor_lnum
  while end_lnum < #lines and line_starts_with_comment(lines[end_lnum + 1], marker) do
    end_lnum = end_lnum + 1
  end

  if start_lnum == end_lnum then
    return nil
  end

  local parts = {}
  for lnum = start_lnum, end_lnum do
    table.insert(parts, strip_leading_comment(lines[lnum], marker))
  end

  local text = collapse_text(parts)
  if text == '' then
    return nil
  end

  return text
end

local function extract_multiline_block_comment(bufnr, cursor_lnum, style)
  if not style.block_start or not style.block_end then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local open_lnum
  local open_col

  for lnum = 1, cursor_lnum do
    local line = lines[lnum]
    local search_col = 1

    while true do
      local start_idx = line:find(style.block_start, search_col, true)
      local end_idx = line:find(style.block_end, search_col, true)
      if not start_idx and not end_idx then
        break
      end

      if start_idx and (not end_idx or start_idx < end_idx) then
        open_lnum = lnum
        open_col = start_idx
        search_col = start_idx + #style.block_start
      else
        open_lnum = nil
        open_col = nil
        search_col = end_idx + #style.block_end
      end
    end
  end

  if not open_lnum then
    return nil
  end

  local close_lnum
  local close_col
  for lnum = open_lnum, #lines do
    local search_col = 1
    if lnum == open_lnum then
      search_col = open_col + #style.block_start
    end

    local end_idx = lines[lnum]:find(style.block_end, search_col, true)
    if end_idx then
      close_lnum = lnum
      close_col = end_idx
      break
    end
  end

  if not close_lnum or close_lnum == open_lnum then
    return nil
  end

  if cursor_lnum < open_lnum or cursor_lnum > close_lnum then
    return nil
  end

  local parts = {}
  for lnum = open_lnum, close_lnum do
    local line = lines[lnum]
    if lnum == open_lnum then
      line = line:sub(open_col + #style.block_start)
    end

    if lnum == close_lnum then
      line = line:sub(1, close_col - 1)
    end

    line = line:gsub('^%s*%*%s?', '')
    table.insert(parts, line)
  end

  local text = collapse_text(parts)
  if text == '' then
    return nil
  end

  return text
end

local function extract_trailing_line_comment(line, marker)
  if not marker then
    return nil
  end

  local comment_col = line:find(marker, 1, true)
  if not comment_col or vim.trim(line:sub(1, comment_col - 1)) == '' then
    return nil
  end

  local text = vim.trim(line:sub(comment_col + #marker))
  if text == '' then
    return nil
  end

  return text
end

local function extract_trailing_block_comment(line, style)
  if not style.block_start or not style.block_end then
    return nil
  end

  local start_idx = line:find(style.block_start, 1, true)
  if not start_idx or vim.trim(line:sub(1, start_idx - 1)) == '' then
    return nil
  end

  local end_idx = line:find(style.block_end, start_idx + #style.block_start, true)
  if not end_idx then
    return nil
  end

  local text = collapse_text({
    line:sub(start_idx + #style.block_start, end_idx - 1),
  })

  if text == '' then
    return nil
  end

  return text
end

local function extract_single_comment_line(line, style)
  if style.line and line_starts_with_comment(line, style.line) then
    return collapse_text({
      strip_leading_comment(line, style.line),
    })
  end

  if style.block_start and style.block_end then
    local start_idx = line:find(style.block_start, 1, true)
    local end_idx = start_idx and line:find(style.block_end, start_idx + #style.block_start, true) or nil
    if start_idx and end_idx then
      return collapse_text({
        line:sub(start_idx + #style.block_start, end_idx - 1),
      })
    end
  end

  return nil
end

local function resolve_translation_target()
  local selection = context.get_visual_selection()
  if selection and vim.trim(selection) ~= '' then
    return selection
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_lnum = vim.api.nvim_win_get_cursor(0)[1]
  local current_line = vim.api.nvim_buf_get_lines(bufnr, cursor_lnum - 1, cursor_lnum, false)[1] or ''
  local style = get_comment_style(bufnr)

  if not style then
    return current_line
  end

  local multiline_block = extract_multiline_block_comment(bufnr, cursor_lnum, style)
  if multiline_block then
    return multiline_block
  end

  local multiline_line = extract_multiline_line_comment(bufnr, cursor_lnum, style.line)
  if multiline_line then
    return multiline_line
  end

  local trailing_line = extract_trailing_line_comment(current_line, style.line)
  if trailing_line then
    return trailing_line
  end

  local trailing_block = extract_trailing_block_comment(current_line, style)
  if trailing_block then
    return trailing_block
  end

  local single_comment = extract_single_comment_line(current_line, style)
  if single_comment and single_comment ~= '' then
    return single_comment
  end

  return current_line
end

function M.translate()
  local text = resolve_translation_target()
  if not text or vim.trim(text) == '' then
    vim.notify('No text available for translation.', vim.log.levels.WARN)
    return
  end

  local pair = resolve_language_pair(text)
  local model_ref = get_model_ref()
  local prompt = build_prompt(text, pair)

  render_float({ 'Translating with ' .. model_ref .. ' ...' }, ' LLM Translation ')

  client.request(model_ref, prompt, { temperature = 0 }, function(translated, err, metadata)
    if err then
      show_error(err)
      return
    end

    render_float(
      vim.split(translated, '\n', { plain = true }),
      string.format(' Translation %s -> %s (%s/%s) ', pair.source_code, pair.target_code, metadata.provider, metadata.model)
    )
  end)
end

function M.translate_visual_selection()
  M.translate()
end

return M
