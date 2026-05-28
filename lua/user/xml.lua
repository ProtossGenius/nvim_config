local M = {}

local state = {}

local function tokenize(bufnr)
  local tokens = {}
  local stack = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  for line_nr, line in ipairs(lines) do
    local search_from = 1
    while true do
      local start_col, end_col, closing, name, attrs, self_closing = line:find('<(/?)([%w_:%.%-]+)(.-)(/?)>', search_from)
      if not start_col then
        break
      end

      local token = {
        line = line_nr,
        name = name,
        name_start = start_col + (closing == '/' and 2 or 1),
        name_end = start_col + (closing == '/' and 1 or 0) + #name,
        kind = closing == '/' and 'end' or 'start',
      }

      local attr_tail = attrs or ''
      if token.kind == 'start' and (self_closing == '/' or attr_tail:match('/%s*$')) then
        token.kind = 'self'
      end

      tokens[#tokens + 1] = token
      local token_index = #tokens

      if token.kind == 'start' then
        stack[#stack + 1] = token_index
      elseif token.kind == 'end' then
        local top_index = stack[#stack]
        if top_index and tokens[top_index].name == token.name then
          tokens[top_index].pair = token_index
          token.pair = top_index
          table.remove(stack)
        end
      end

      search_from = end_col + 1
    end
  end

  return tokens
end

local function find_token_at(tokens, line_nr, col)
  for index, token in ipairs(tokens) do
    if token.line == line_nr and token.kind ~= 'self' then
      local start_col = token.name_start - 1
      local end_col = token.name_end - 1
      if col >= start_col and col <= end_col then
        return token, index
      end
    end
  end
end

local function find_token_near(tokens, line_nr, kind, name_start)
  local best_token
  local best_index
  local best_distance

  for index, token in ipairs(tokens) do
    if token.line == line_nr and token.kind == kind then
      local distance = math.abs(token.name_start - name_start)
      if not best_distance or distance < best_distance then
        best_token = token
        best_index = index
        best_distance = distance
      end
    end
  end

  return best_token, best_index
end

local function session_for(bufnr)
  if not state[bufnr] then
    state[bufnr] = {}
  end
  return state[bufnr]
end

local function capture_session(bufnr, preserve_existing)
  local session = session_for(bufnr)
  if session.updating then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local tokens = tokenize(bufnr)
  local token, token_index = find_token_at(tokens, cursor[1], cursor[2])
  if not token or not token.pair then
    if not preserve_existing then
      session.edit = nil
    end
    return
  end

  local pair = tokens[token.pair]
  if not pair or pair.name ~= token.name then
    session.edit = nil
    return
  end

  session.edit = {
    line = token.line,
    kind = token.kind,
    name_start = token.name_start,
    original_name = token.name,
    pair_name = pair.name,
    pair_line = pair.line,
    pair_name_start = pair.name_start,
    pair_kind = pair.kind,
  }
end

local function apply_pair_rename(bufnr)
  local session = session_for(bufnr)
  local edit = session.edit
  if not edit or session.updating then
    return
  end

  local tokens = tokenize(bufnr)
  local token = select(1, find_token_at(tokens, vim.api.nvim_win_get_cursor(0)[1], vim.api.nvim_win_get_cursor(0)[2]))
  if not token or token.kind ~= edit.kind then
    token = select(1, find_token_near(tokens, edit.line, edit.kind, edit.name_start))
  end

  if not token or token.kind == 'self' then
    session.edit = nil
    return
  end

  local pair = select(1, find_token_near(tokens, edit.pair_line, edit.pair_kind, edit.pair_name_start))
  if not pair or pair.name ~= edit.pair_name then
    session.edit = nil
    return
  end

  if token.name == edit.original_name or token.name == pair.name then
    session.edit = nil
    return
  end

  session.updating = true
  vim.api.nvim_buf_set_text(
    bufnr,
    pair.line - 1,
    pair.name_start - 1,
    pair.line - 1,
    pair.name_end,
    { token.name }
  )
  session.updating = false
  session.edit = nil
end

function M.setup()
  local group = vim.api.nvim_create_augroup('UserXmlTagSync', { clear = true })

  vim.api.nvim_create_autocmd('InsertEnter', {
    group = group,
    pattern = '*',
    callback = function(args)
      if vim.bo[args.buf].filetype == 'xml' then
        capture_session(args.buf, true)
      end
    end,
  })

  vim.api.nvim_create_autocmd('CursorMoved', {
    group = group,
    pattern = '*',
    callback = function(args)
      if vim.bo[args.buf].filetype == 'xml' then
        capture_session(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    pattern = '*',
    callback = function(args)
      if vim.bo[args.buf].filetype == 'xml' then
        apply_pair_rename(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    pattern = '*',
    callback = function(args)
      state[args.buf] = nil
    end,
  })
end

return M
