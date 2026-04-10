-- [[ user.translate ]]
-- Visual translation via local Ollama.

local M = {}

local state = {
  buf = nil,
  win = nil,
}

local function get_model()
  return vim.g.ollama_translate_model or 'translategemma:4b'
end

local function get_endpoint()
  return vim.g.ollama_translate_endpoint or 'http://127.0.0.1:11434/api/generate'
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

local function get_visual_selection()
  local mode = vim.fn.visualmode()
  if mode == '\022' then
    vim.notify('Blockwise visual mode is not supported for translation.', vim.log.levels.WARN)
    return nil
  end

  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_row, start_col = start_pos[2], start_pos[3]
  local end_row, end_col = end_pos[2], end_pos[3]

  if start_row > end_row or (start_row == end_row and start_col > end_col) then
    start_row, end_row = end_row, start_row
    start_col, end_col = end_col, start_col
  end

  if mode == 'V' then
    return table.concat(vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false), '\n')
  end

  local lines = vim.api.nvim_buf_get_text(0, start_row - 1, start_col - 1, end_row - 1, end_col, {})
  return table.concat(lines, '\n')
end

local function show_error(message)
  render_float(vim.split(message, '\n', { plain = true }), ' Ollama Translation Error ')
end

function M.translate_visual_selection()
  local text = get_visual_selection()
  if not text or vim.trim(text) == '' then
    vim.notify('No text selected for translation.', vim.log.levels.WARN)
    return
  end

  local pair = resolve_language_pair(text)
  local model = get_model()
  local prompt = build_prompt(text, pair)

  render_float({ 'Translating with ' .. model .. ' ...' }, ' Ollama Translation ')

  vim.system({
    'curl',
    '-sS',
    get_endpoint(),
    '-H',
    'Content-Type: application/json',
    '-d',
    vim.json.encode({
      model = model,
      prompt = prompt,
      stream = false,
      options = {
        temperature = 0,
      },
    }),
  }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local message = vim.trim(result.stderr ~= '' and result.stderr or result.stdout)
        show_error(message ~= '' and message or 'Failed to connect to local Ollama.')
        return
      end

      local ok, payload = pcall(vim.json.decode, result.stdout)
      if not ok then
        show_error('Invalid response from local Ollama.')
        return
      end

      if payload.error then
        show_error(payload.error)
        return
      end

      local translated = vim.trim(payload.response or '')
      if translated == '' then
        show_error('Ollama returned an empty translation.')
        return
      end

      render_float(
        vim.split(translated, '\n', { plain = true }),
        string.format(' Translation %s -> %s ', pair.source_code, pair.target_code)
      )
    end)
  end)
end

return M
