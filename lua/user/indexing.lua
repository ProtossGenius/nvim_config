local uv = vim.uv or vim.loop

local M = {}

local function normalize(path)
  if not path or path == '' then
    return nil
  end

  path = tostring(path)
  local expanded = path
  if path:sub(1, 1) == '~' or path:find('$', 1, true) then
    local ok, result = pcall(vim.fn.expand, path)
    if ok and result and result ~= '' then
      expanded = result
    end
  end

  local ok, normalized = pcall(vim.fs.normalize, expanded)
  if not ok then
    return nil
  end
  return normalized
end

local function as_list(value)
  if value == nil then
    return {}
  end
  if type(value) == 'string' then
    return { value }
  end
  if type(value) == 'table' then
    return value
  end
  return {}
end

local function is_same_or_child(path, root)
  if not path or not root then
    return false
  end
  if root == '/' then
    return path == '/'
  end
  return path == root or path:sub(1, #root + 1) == root .. '/'
end

local function no_auto_index_entries()
  local entries = {}

  for _, path in ipairs(as_list(vim.g.no_auto_index_dirs)) do
    table.insert(entries, { path = path, recursive = false })
  end

  for _, path in ipairs(as_list(vim.g.no_auto_index_recursive_dirs)) do
    table.insert(entries, { path = path, recursive = true })
  end

  return entries
end

function M.is_no_auto_index_dir(path)
  local normalized = normalize(path)
  if not normalized then
    return false
  end

  for _, entry in ipairs(no_auto_index_entries()) do
    local entry_path = entry.path
    local recursive = entry.recursive
    if type(entry_path) == 'table' then
      recursive = entry_path.recursive == true
      entry_path = entry_path.path or entry_path[1]
    end

    if type(entry_path) == 'string' and entry_path ~= '' then
      if entry_path:sub(-3) == '/**' then
        recursive = true
        entry_path = entry_path:sub(1, -4)
      end

      local normalized_entry = normalize(entry_path)
      if normalized_entry then
        if recursive and is_same_or_child(normalized, normalized_entry) then
          return true
        end
        if not recursive and normalized == normalized_entry then
          return true
        end
      end
    end
  end

  return false
end

function M.search_cwd(opts)
  opts = opts or {}
  if opts.cwd and opts.cwd ~= '' then
    return normalize(opts.cwd) or opts.cwd
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local protected_dir = vim.b[bufnr].user_no_auto_index_dir
  if protected_dir and protected_dir ~= '' then
    return normalize(protected_dir) or protected_dir
  end

  return normalize(_G.initial_cwd or vim.fn.getcwd()) or vim.fn.getcwd()
end

function M.realtime_search_min_chars()
  return tonumber(vim.g.no_auto_index_min_search_chars) or 2
end

function M.directory_placeholder(dir)
  local normalized = normalize(dir) or tostring(dir)
  return {
    'No automatic indexing for this directory.',
    '',
    normalized,
    '',
    'Use <C-p> or SPC f a to search files here after typing a query.',
    'Use <A-f> or SPC f g to live-grep here after typing a query.',
    'Run :Dirvish ' .. vim.fn.fnameescape(normalized) .. ' if you explicitly want a directory listing.',
  }
end

function M.show_directory_placeholder(dir, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local normalized = normalize(dir) or tostring(dir)

  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].bufhidden = 'hide'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, M.directory_placeholder(normalized))
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = 'noautoindex'
  vim.b[bufnr].user_no_auto_index_dir = normalized
end

function M.guard_directory_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.b[bufnr].user_no_auto_index_dir then
    return true
  end
  if vim.bo[bufnr].bufhidden:match('unload') or vim.bo[bufnr].bufhidden:match('delete') or vim.bo[bufnr].bufhidden:match('wipe') then
    return false
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  local normalized = normalize(name)
  local stat = normalized and uv.fs_stat(normalized) or nil
  if not stat or stat.type ~= 'directory' then
    return false
  end

  if M.is_no_auto_index_dir(normalized) then
    M.show_directory_placeholder(normalized, bufnr)
    return true
  end

  return false
end

function M.dirvish_buf_enter()
  if M.guard_directory_buffer(0) then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local has_dirvish = vim.b[bufnr].dirvish ~= nil
  local name = vim.api.nvim_buf_get_name(bufnr)
  local stat = name ~= '' and uv.fs_stat(name) or nil
  if not has_dirvish and stat and stat.type == 'directory' then
    vim.cmd('Dirvish')
  elseif has_dirvish and vim.bo[bufnr].buflisted and vim.fn.bufnr('$') > 1 then
    vim.bo[bufnr].buflisted = false
  end
end

M._test = {
  normalize = normalize,
  is_same_or_child = is_same_or_child,
}

return M
