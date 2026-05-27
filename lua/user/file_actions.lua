local uv = vim.uv or vim.loop

local M = {}

local function fs_stat(path)
  return path ~= '' and uv.fs_stat(path) or nil
end

local function normalize_path(path)
  if not path or path == '' then
    return nil
  end

  return vim.fs.normalize(path)
end

local function path_info(path)
  local normalized = normalize_path(path)
  if not normalized then
    return nil
  end

  local stat = fs_stat(normalized)
  if not stat then
    return nil
  end

  return {
    path = normalized,
    is_directory = stat.type == 'directory',
  }
end

local function buf_name(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    return nil
  end

  return normalize_path(name)
end

local function starts_with_path(path, prefix)
  return path == prefix or path:sub(1, #prefix + 1) == prefix .. '/'
end

local function rename_loaded_buffers(old_path, new_path, is_directory)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local name = buf_name(bufnr)
      local replacement

      if name then
        if is_directory and starts_with_path(name, old_path) then
          replacement = new_path .. name:sub(#old_path + 1)
        elseif name == old_path then
          replacement = new_path
        end
      end

      if replacement and replacement ~= name then
        local existing_bufnr = vim.fn.bufnr(replacement)
        if existing_bufnr > 0 and existing_bufnr ~= bufnr then
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(win) == bufnr then
              vim.api.nvim_win_set_buf(win, existing_bufnr)
            end
          end
          vim.api.nvim_buf_delete(bufnr, { force = true })
        else
          vim.api.nvim_buf_set_name(bufnr, replacement)
        end
      end
    end
  end
end

local function collect_workspace_edit_buffers(edit)
  local bufnrs = {}
  local seen = {}

  local function add_uri(uri)
    if not uri or seen[uri] then
      return
    end

    seen[uri] = true
    local bufnr = vim.uri_to_bufnr(uri)
    if bufnr > 0 then
      vim.fn.bufload(bufnr)
      table.insert(bufnrs, bufnr)
    end
  end

  for uri, _ in pairs(edit.changes or {}) do
    add_uri(uri)
  end

  for _, change in ipairs(edit.documentChanges or {}) do
    if change.textDocument and change.textDocument.uri then
      add_uri(change.textDocument.uri)
    end
  end

  return bufnrs
end

local function write_modified_buffers(bufnrs)
  for _, bufnr in ipairs(bufnrs) do
    if vim.api.nvim_buf_is_valid(bufnr)
      and vim.api.nvim_buf_is_loaded(bufnr)
      and vim.bo[bufnr].buftype == ''
      and vim.bo[bufnr].modifiable
      and vim.bo[bufnr].modified
    then
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd('silent write')
      end)
    end
  end
end

local function find_jdtls_client(path)
  local best_client
  local best_root_len = -1

  for _, client in ipairs(vim.lsp.get_clients({ name = 'jdtls' })) do
    local roots = {}

    if client.config and client.config.root_dir then
      table.insert(roots, client.config.root_dir)
    end

    for _, folder in ipairs(client.workspace_folders or {}) do
      table.insert(roots, vim.uri_to_fname(folder.uri))
    end

    for _, root in ipairs(roots) do
      local normalized_root = normalize_path(root)
      if normalized_root and starts_with_path(path, normalized_root) and #normalized_root > best_root_len then
        best_client = client
        best_root_len = #normalized_root
      end
    end
  end

  return best_client
end

local function find_java_type_position(bufnr, type_name)
  local line_count = math.min(vim.api.nvim_buf_line_count(bufnr), 200)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, line_count, false)
  local escaped = vim.pesc(type_name)
  local declaration_patterns = {
    '@interface%s+()' .. escaped .. '%f[^%w_]',
    'class%s+()' .. escaped .. '%f[^%w_]',
    'interface%s+()' .. escaped .. '%f[^%w_]',
    'enum%s+()' .. escaped .. '%f[^%w_]',
    'record%s+()' .. escaped .. '%f[^%w_]',
  }

  for line_index, line in ipairs(lines) do
    for _, pattern in ipairs(declaration_patterns) do
      local start_col = line:match(pattern)
      if start_col then
        return {
          line = line_index - 1,
          character = start_col - 1,
        }
      end
    end
  end

  for line_index, line in ipairs(lines) do
    local start_col = line:find(type_name, 1, true)
    if start_col then
      return {
        line = line_index - 1,
        character = start_col - 1,
      }
    end
  end
end

local function rename_java_type(client, bufnr, old_type_name, new_type_name)
  if old_type_name == new_type_name then
    return true, {}
  end

  local position = find_java_type_position(bufnr, old_type_name)
  if not position then
    return false, 'Could not find the Java type declaration to rename.'
  end

  local response = client:request_sync('textDocument/rename', {
    newName = new_type_name,
    position = position,
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
  }, 30000, bufnr)

  if not response then
    return false, 'Timed out waiting for jdtls to rename the Java type.'
  end

  if response.err then
    return false, response.err.message or 'jdtls rejected the Java type rename.'
  end

  if not response.result then
    return true, {}
  end

  local touched_bufnrs = collect_workspace_edit_buffers(response.result)
  vim.lsp.util.apply_workspace_edit(response.result, client.offset_encoding or 'utf-16')
  write_modified_buffers(touched_bufnrs)
  return true, touched_bufnrs
end

local function apply_java_file_rename(old_path, new_path)
  local client = find_jdtls_client(old_path)
  if not client then
    return false, 'No active jdtls client found for this Java file.'
  end

  local rename_files = {
    files = {
      {
        oldUri = vim.uri_from_fname(old_path),
        newUri = vim.uri_from_fname(new_path),
      },
    },
  }

  local bufnr = vim.fn.bufnr(old_path, true)
  if bufnr > 0 then
    vim.fn.bufload(bufnr)
  end

  local touched_bufnrs = {}
  if bufnr <= 0 then
    return false, 'Could not load the Java buffer for renaming.'
  end

  local old_type_name = vim.fn.fnamemodify(old_path, ':t:r')
  local new_type_name = vim.fn.fnamemodify(new_path, ':t:r')
  local renamed_type, rename_result = rename_java_type(client, bufnr, old_type_name, new_type_name)
  if not renamed_type then
    return false, rename_result
  end
  touched_bufnrs = rename_result or {}

  if not fs_stat(new_path) or fs_stat(old_path) then
    local ok, err = os.rename(old_path, new_path)
    if not ok then
      return false, err
    end
  end

  rename_loaded_buffers(old_path, new_path, false)
  if bufnr > 0 then
    table.insert(touched_bufnrs, bufnr)
  end

  if client:supports_method('workspace/didRenameFiles') then
    client:notify('workspace/didRenameFiles', rename_files)
  end

  return true
end

local function confirm_delete(path, is_directory, skip_confirm)
  if skip_confirm then
    return true
  end

  local kind = is_directory and 'directory' or 'file'
  local name = vim.fn.fnamemodify(path, ':t')
  local choice = vim.fn.confirm(
    string.format('Delete %s "%s"?', kind, name),
    '&Yes\n&No',
    2
  )

  return choice == 1
end

local function ensure_target_available(path)
  local info = path_info(path)
  if info then
    return info
  end

  vim.notify('Target path is not available: ' .. tostring(path), vim.log.levels.ERROR)
  return nil
end

local function refresh_callback(opts)
  if opts and type(opts.refresh) == 'function' then
    opts.refresh()
  end
end

function M.create_path(path, opts)
  opts = opts or {}

  local target_path = normalize_path(path)
  if not target_path then
    vim.notify('Invalid create target: ' .. tostring(path), vim.log.levels.ERROR)
    return false
  end

  if fs_stat(target_path) then
    vim.notify('Create failed: target already exists: ' .. vim.fn.fnamemodify(target_path, ':t'), vim.log.levels.ERROR)
    return false
  end

  local parent_dir = vim.fn.fnamemodify(target_path, ':h')
  if parent_dir == '' or parent_dir == '.' then
    parent_dir = vim.fn.getcwd()
  end

  if vim.fn.mkdir(parent_dir, 'p') ~= 1 and not fs_stat(parent_dir) then
    vim.notify('Create failed: could not create parent directory: ' .. parent_dir, vim.log.levels.ERROR)
    return false
  end

  local ok, err = pcall(vim.fn.writefile, {}, target_path)
  if not ok then
    vim.notify('Create failed: ' .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  refresh_callback(opts)

  if opts.open_after_create then
    vim.cmd((opts.open_cmd or 'edit') .. ' ' .. vim.fn.fnameescape(target_path))
  end

  vim.notify('Created ' .. vim.fn.fnamemodify(target_path, ':t'), vim.log.levels.INFO)
  return true
end

function M.rename_path(path, opts)
  opts = opts or {}

  local info = ensure_target_available(path)
  if not info then
    return false
  end

  local old_path = info.path
  local old_name = vim.fn.fnamemodify(old_path, ':t')
  local new_name = opts.new_name or vim.fn.input('Rename ' .. old_name .. ' to: ', old_name)
  if new_name == '' or new_name == old_name then
    return false
  end

  local parent_dir = vim.fn.fnamemodify(old_path, ':h')
  local new_path = normalize_path(vim.fs.joinpath(parent_dir, new_name))
  if not new_path then
    vim.notify('Invalid rename target: ' .. tostring(new_name), vim.log.levels.ERROR)
    return false
  end

  if fs_stat(new_path) then
    vim.notify('Rename failed: target already exists: ' .. new_name, vim.log.levels.ERROR)
    return false
  end

  local ok, err
  if not info.is_directory and old_path:match('%.java$') then
    ok, err = apply_java_file_rename(old_path, new_path)
  else
    ok, err = os.rename(old_path, new_path)
    if ok then
      rename_loaded_buffers(old_path, new_path, info.is_directory)
    end
  end

  if not ok then
    vim.notify('Rename failed: ' .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  refresh_callback(opts)
  vim.notify('Successfully renamed ' .. old_name .. ' to ' .. new_name, vim.log.levels.INFO)
  return true
end

function M.delete_path(path, opts)
  opts = opts or {}

  local info = ensure_target_available(path)
  if not info then
    return false
  end

  if not confirm_delete(info.path, info.is_directory, opts.skip_confirm) then
    return false
  end

  local result = vim.fn.delete(info.path, info.is_directory and 'rf' or '')
  if result ~= 0 then
    vim.notify('Delete failed: ' .. info.path, vim.log.levels.ERROR)
    return false
  end

  refresh_callback(opts)
  vim.notify(
    'Deleted ' .. vim.fn.fnamemodify(info.path, ':t') .. ' from disk; open buffers were kept.',
    vim.log.levels.INFO
  )
  return true
end

function M.rename_current_buffer()
  local name = vim.api.nvim_buf_get_name(0)
  if name == '' then
    vim.notify('Current buffer is not backed by a file.', vim.log.levels.WARN)
    return
  end

  M.rename_path(name)
end

function M.delete_current_buffer_file()
  local name = vim.api.nvim_buf_get_name(0)
  if name == '' then
    vim.notify('Current buffer is not backed by a file.', vim.log.levels.WARN)
    return
  end

  M.delete_path(name)
end

return M
