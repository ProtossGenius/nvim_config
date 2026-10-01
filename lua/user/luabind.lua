local project = require('user.project')

local M = {}

-- Cache storage: root -> { mtimes = { [file] = mtime }, methods = { ... }, by_name = { ... }, by_class = { ... } }
local cache = {}

local function normalize(path)
  if not path or path == '' then
    return nil
  end
  return vim.fs.normalize(path)
end

function M.clear_cache(root)
  if root then
    cache[normalize(root)] = nil
  else
    cache = {}
  end
end

-- Resolve project root with priority to .git, .root, .proj
function M.get_project_root(path_or_bufnr)
  local base_path
  if type(path_or_bufnr) == 'number' then
    base_path = project.path_from_buf(path_or_bufnr)
  elseif type(path_or_bufnr) == 'string' then
    base_path = normalize(path_or_bufnr)
  else
    base_path = project.path_from_buf(0)
  end

  base_path = base_path or vim.fn.getcwd()

  -- Check priority root markers: .root, .proj, .git
  local priority_root = vim.fs.root(base_path, { '.root', '.proj', '.git' })
  if priority_root then
    return normalize(priority_root)
  end

  local pr = project.root(base_path)
  if pr then
    return normalize(pr)
  end

  return normalize(vim.fn.getcwd())
end

-- Get .luabind directory or file under root
function M.get_luabind_path(root)
  local r = root or M.get_project_root(0)
  if not r then
    return nil
  end

  local candidate = vim.fs.joinpath(r, '.luabind')
  local stat = vim.uv.fs_stat(candidate)
  if stat then
    return normalize(candidate), stat.type
  end

  return nil
end

function M.has_luabind(root_or_bufnr)
  local root
  if type(root_or_bufnr) == 'string' and vim.uv.fs_stat(root_or_bufnr) then
    -- Check if it's already the root or a path
    root = root_or_bufnr
    local candidate = vim.fs.joinpath(root, '.luabind')
    if vim.uv.fs_stat(candidate) then
      return true
    end
  end

  root = M.get_project_root(root_or_bufnr)
  local path = M.get_luabind_path(root)
  return path ~= nil
end

function M.is_luabind_buffer(bufnr)
  bufnr = bufnr or 0
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then return false end
  local norm = vim.fs.normalize(name)
  if norm:find('/%.luabind/') or norm:find('%.luabind$') then
    return true
  end
  return false
end

-- Collect all files to scan within .luabind
local function collect_luabind_files(luabind_path, path_type)
  if path_type == 'file' then
    return { luabind_path }
  end

  local files = {}
  local function scan_dir(dir)
    local handle = vim.uv.fs_scandir(dir)
    if not handle then return end

    while true do
      local name, t = vim.uv.fs_scandir_next(handle)
      if not name then break end
      if name ~= '.' and name ~= '..' and name ~= '.git' and not name:match('^%.luabind_meta') then
        local full_path = vim.fs.joinpath(dir, name)
        if t == 'directory' then
          scan_dir(full_path)
        elseif t == 'file' then
          -- Support C/C++, Luabind, and Lua files or general text
          local ext = vim.fn.fnamemodify(name, ':e'):lower()
          if ext == 'cpp' or ext == 'h' or ext == 'hpp' or ext == 'c' or ext == 'cc'
            or ext == 'cxx' or ext == 'hxx' or ext == 'luabind' or ext == 'lua' or ext == '' then
            table.insert(files, normalize(full_path))
          end
        end
      end
    end
  end

  scan_dir(luabind_path)
  table.sort(files)
  return files
end

-- Clean comment lines and extract text
local function clean_comment_line(line)
  local s = line:match('^%s*//+[/]?(.*)$')
  if s then return vim.trim(s) end
  s = line:match('^%s*%-%-+[-]*(.*)$')
  if s then return vim.trim(s) end
  return nil
end

-- Parse a single file for C++ / Luabind / Lua methods
function M.parse_file(file_path)
  local stat = vim.uv.fs_stat(file_path)
  if not stat or stat.type ~= 'file' then
    return {}
  end

  local ok, lines = pcall(vim.fn.readfile, file_path)
  if not ok or not lines then
    return {}
  end

  local methods = {}
  local pending_comments = {}
  local current_class = nil
  local in_block_comment = false
  local block_comment_lines = {}

  local skip_keywords = {
    ['if'] = true, ['for'] = true, ['while'] = true, ['switch'] = true,
    ['catch'] = true, ['return'] = true, ['else'] = true, ['case'] = true,
    ['typedef'] = true, ['using'] = true, ['namespace'] = true, ['template'] = true,
    ['public'] = true, ['private'] = true, ['protected'] = true, ['sizeof'] = true,
  }

  local i = 1
  while i <= #lines do
    local line = lines[i]
    local trimmed = vim.trim(line)

    -- Block comment handling (/* ... */)
    if in_block_comment then
      local end_idx = line:find('%*/')
      if end_idx then
        local comment_part = line:sub(1, end_idx - 1)
        comment_part = comment_part:gsub('^%s*%*?', '')
        table.insert(block_comment_lines, vim.trim(comment_part))
        in_block_comment = false
        for _, cl in ipairs(block_comment_lines) do
          if cl ~= '' then table.insert(pending_comments, cl) end
        end
        block_comment_lines = {}
      else
        local comment_part = line:gsub('^%s*%*?', '')
        table.insert(block_comment_lines, vim.trim(comment_part))
      end
      i = i + 1
      goto continue
    end

    if trimmed:find('^/%*') then
      if trimmed:find('%*/') then
        local inside = trimmed:match('^/%*+[%s]*(.-)%*+/$')
        if inside and inside ~= '' then
          table.insert(pending_comments, vim.trim(inside))
        end
      else
        in_block_comment = true
        block_comment_lines = {}
        local inside = trimmed:match('^/%*+[%s]*(.*)$')
        if inside and inside ~= '' then
          table.insert(block_comment_lines, vim.trim(inside))
        end
      end
      i = i + 1
      goto continue
    end

    -- Line comment handling (// or --)
    local line_cmt = clean_comment_line(line)
    if line_cmt then
      if line_cmt ~= '' then
        table.insert(pending_comments, line_cmt)
      end
      i = i + 1
      goto continue
    end

    -- Blank line
    if trimmed == '' then
      i = i + 1
      goto continue
    end

    -- Class / struct detection
    local class_match = trimmed:match('^class%s+([%w_]+)') or trimmed:match('^struct%s+([%w_]+)')
    if class_match then
      current_class = class_match
      pending_comments = {}
      i = i + 1
      goto continue
    end

    if current_class and trimmed:find('^}%s*;') then
      current_class = nil
      pending_comments = {}
      i = i + 1
      goto continue
    end

    -- Check for Luabind registration def("name", ...)
    local def_name, def_target = trimmed:match('def%s*%(%s*["\']([%w_]+)["\']%s*,%s*&?([%w_:]+)')
    if def_name then
      local m_class = current_class
      if def_target and def_target:find('::') then
        m_class = def_target:match('^([%w_]+)::')
      end
      local col_idx = (line:find(def_name, 1, true) or 1) - 1
      table.insert(methods, {
        name = def_name,
        class_name = m_class,
        signature = (m_class and (m_class .. '::') or '') .. def_name,
        doc_comments = vim.deepcopy(pending_comments),
        body_comments = {},
        file = file_path,
        line = i,
        col = col_idx,
        has_body = false,
      })
      pending_comments = {}
      i = i + 1
      goto continue
    end

    -- Check for Lua function definition
    local lua_class, lua_func, lua_params = trimmed:match('^function%s+([%w_]+)[.:]([%w_]+)%s*%((.-)%)')
    if not lua_func then
      lua_func, lua_params = trimmed:match('^function%s+([%w_]+)%s*%((.-)%)')
    end
    if lua_func then
      local body_comments = {}
      local start_line = i
      local col_idx = (line:find(lua_func, 1, true) or 1) - 1
      local depth = 1
      i = i + 1
      while i <= #lines and depth > 0 do
        local bline = lines[i]
        local btrim = vim.trim(bline)
        if btrim:match('^function%f[%s%(]') or btrim:match('^if%f[%s%(]') or btrim:match('^for%f[%s%(]') or btrim:match('^while%f[%s%(]') then
          depth = depth + 1
        elseif btrim == 'end' or btrim:match('^end%f[%s;,%)]') then
          depth = depth - 1
        end
        local cmt = clean_comment_line(bline)
        if cmt and cmt ~= '' then
          table.insert(body_comments, cmt)
        end
        i = i + 1
      end
      table.insert(methods, {
        name = lua_func,
        class_name = lua_class,
        params = lua_params,
        signature = string.format('%s%s(%s)', lua_class and (lua_class .. ':') or '', lua_func, lua_params or ''),
        doc_comments = vim.deepcopy(pending_comments),
        body_comments = body_comments,
        file = file_path,
        line = start_line,
        col = col_idx,
        has_body = #body_comments > 0,
      })
      pending_comments = {}
      goto continue
    end

    -- Check for C++ function declaration / definition
    if trimmed:find('%(') and not trimmed:find('^#') then
      local sig_text = trimmed
      local sig_start_line = i
      while not sig_text:find('%)') and i < #lines do
        i = i + 1
        sig_text = sig_text .. ' ' .. vim.trim(lines[i])
      end

      local before_paren, params, after_paren = sig_text:match('^(.-)%((.-)%)(.*)$')
      if before_paren then
        local b = vim.trim(before_paren)
        local ret_type, class_part, fn_name
        if b:find('::') then
          class_part, fn_name = b:match('([%w_]+)::([%w_]+)$')
          ret_type = b:match('^(.-)%s+[%w_]+::[%w_]+$')
        else
          ret_type, fn_name = b:match('^(.-)%s+([%w_]+)$')
          if not fn_name then
            fn_name = b:match('^([%w_]+)$')
          end
        end

        if fn_name and not skip_keywords[fn_name] and not skip_keywords[ret_type] then
          local actual_class = class_part or current_class
          ret_type = ret_type and vim.trim(ret_type) or nil
          if ret_type then
            ret_type = ret_type:gsub('^virtual%s+', ''):gsub('^static%s+', ''):gsub('^inline%s+', ''):gsub('^explicit%s+', '')
          end

          local col_idx = (lines[sig_start_line]:find(fn_name, 1, true) or 1) - 1
          local body_comments = {}

          local has_body = (after_paren and after_paren:find('{') ~= nil)
          if not has_body and after_paren and not after_paren:find(';') then
            if i + 1 <= #lines and lines[i + 1]:find('^%s*{') then
              has_body = true
              i = i + 1
            end
          end

          if has_body then
            local brace_depth = 1
            local cur_line_after_brace = lines[i]:sub((lines[i]:find('{') or 0) + 1)
            for ch in cur_line_after_brace:gmatch('[{}]') do
              if ch == '{' then brace_depth = brace_depth + 1
              elseif ch == '}' then brace_depth = brace_depth - 1 end
            end
            local inline_cmt = cur_line_after_brace:match('//(.*)$') or cur_line_after_brace:match('/%*(.-)%*/')
            if inline_cmt and vim.trim(inline_cmt) ~= '' then
              table.insert(body_comments, vim.trim(inline_cmt))
            end

            i = i + 1
            while i <= #lines and brace_depth > 0 do
              local bline = lines[i]
              local b_cmt = clean_comment_line(bline)
              if b_cmt and b_cmt ~= '' then
                table.insert(body_comments, b_cmt)
              else
                local b_inside = bline:match('/%*(.-)%*/')
                if b_inside and vim.trim(b_inside) ~= '' then
                  table.insert(body_comments, vim.trim(b_inside))
                end
              end

              if not b_cmt then
                local code_only = bline:gsub('//.*$', ''):gsub('/%*.-%*/', '')
                for ch in code_only:gmatch('[{}]') do
                  if ch == '{' then brace_depth = brace_depth + 1
                  elseif ch == '}' then brace_depth = brace_depth - 1 end
                end
              end

              i = i + 1
            end
          else
            i = i + 1
          end

          local sig = string.format('%s%s%s(%s)',
            ret_type and (ret_type .. ' ') or '',
            actual_class and (actual_class .. '::') or '',
            fn_name,
            params or '')

          table.insert(methods, {
            name = fn_name,
            class_name = actual_class,
            return_type = ret_type,
            params = params,
            signature = sig,
            doc_comments = vim.deepcopy(pending_comments),
            body_comments = body_comments,
            file = file_path,
            line = sig_start_line,
            col = col_idx,
            has_body = has_body,
          })
          pending_comments = {}
          goto continue
        end
      end
    end

    if not trimmed:find('^//') and not trimmed:find('^/%*') and trimmed ~= '' then
      pending_comments = {}
    end

    i = i + 1
    ::continue::
  end

  return methods
end

-- Get methods for a root, using cached data if mtimes haven't changed
function M.get_methods(root_or_bufnr)
  local root = M.get_project_root(root_or_bufnr)
  if not root then
    return {}
  end

  local luabind_path, path_type = M.get_luabind_path(root)
  if not luabind_path then
    return {}
  end

  local files = collect_luabind_files(luabind_path, path_type)
  local cached_data = cache[root]

  -- Check if cache is still valid
  local is_valid = cached_data ~= nil
  if is_valid then
    for _, f in ipairs(files) do
      local stat = vim.uv.fs_stat(f)
      local cur_mtime = stat and stat.mtime.sec or 0
      if not cached_data.mtimes[f] or cached_data.mtimes[f] ~= cur_mtime then
        is_valid = false
        break
      end
    end
    if is_valid and #files ~= vim.tbl_count(cached_data.mtimes) then
      is_valid = false
    end
  end

  if is_valid then
    return cached_data.methods
  end

  -- Re-scan all files
  local all_methods = {}
  local by_name = {}
  local by_class = {}
  local by_key = {}
  local mtimes = {}

  for _, file_path in ipairs(files) do
    local stat = vim.uv.fs_stat(file_path)
    mtimes[file_path] = stat and stat.mtime.sec or 0
    local file_methods = M.parse_file(file_path)

    for _, m in ipairs(file_methods) do
      local key = (m.class_name and (m.class_name .. '::') or '') .. m.name
      local existing = by_key[key]

      if existing then
        -- Merge comments: prioritize doc_comments and body_comments
        if #existing.doc_comments == 0 and #m.doc_comments > 0 then
          existing.doc_comments = m.doc_comments
        end
        if #existing.body_comments == 0 and #m.body_comments > 0 then
          existing.body_comments = m.body_comments
        end
        -- Prefer definition line over forward declaration
        if not existing.has_body and m.has_body then
          existing.file = m.file
          existing.line = m.line
          existing.col = m.col
          existing.has_body = true
        end
      else
        by_key[key] = m
        table.insert(all_methods, m)

        by_name[m.name] = by_name[m.name] or {}
        table.insert(by_name[m.name], m)

        if m.class_name then
          by_class[m.class_name] = by_class[m.class_name] or {}
          table.insert(by_class[m.class_name], m)
        end
      end
    end
  end

  cache[root] = {
    mtimes = mtimes,
    methods = all_methods,
    by_name = by_name,
    by_class = by_class,
    by_key = by_key,
  }

  return all_methods
end

-- Find methods matching a name and optional class
function M.find_methods(name, class_name, root_or_bufnr)
  local root = M.get_project_root(root_or_bufnr)
  local cached = cache[root]
  if not cached then
    M.get_methods(root)
    cached = cache[root]
  end

  if not cached then
    return {}
  end

  local candidates = cached.by_name[name] or {}
  if not class_name or class_name == '' then
    return candidates
  end

  local lowered_class = class_name:lower()
  local filtered = {}
  for _, m in ipairs(candidates) do
    if m.class_name and m.class_name:lower() == lowered_class then
      table.insert(filtered, m)
    end
  end

  if #filtered > 0 then
    return filtered
  end

  return candidates
end

-- Format method documentation for completion and hover
function M.format_documentation(method)
  local lines = {}
  table.insert(lines, '```cpp')
  table.insert(lines, method.signature or method.name)
  table.insert(lines, '```')

  local rel_file = project.relative(method.file)
  table.insert(lines, string.format('*Defined in: `%s:%d`*', rel_file, method.line))
  table.insert(lines, '')

  if method.doc_comments and #method.doc_comments > 0 then
    table.insert(lines, '### 📖 Documentation')
    for _, c in ipairs(method.doc_comments) do
      table.insert(lines, c)
    end
    table.insert(lines, '')
  end

  if method.body_comments and #method.body_comments > 0 then
    table.insert(lines, '### 💡 Method Body Comments')
    for _, c in ipairs(method.body_comments) do
      table.insert(lines, c)
    end
    table.insert(lines, '')
  end

  return table.concat(lines, '\n')
end

-- Jump to definition of method under cursor
function M.jump_to_definition(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local root = M.get_project_root(bufnr)
  if not M.has_luabind(root) then
    return false
  end

  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] -- 0-indexed column

  -- Extract method and optional class context around cursor
  local word = vim.fn.expand('<cword>')
  if not word or word == '' then
    return false
  end

  local class_part = nil
  local before = line:sub(1, col + 1)
  local member_prefix = before:match('([%w_]+)[.:][%w_]*$')
  if member_prefix and member_prefix ~= word then
    class_part = member_prefix
  end

  local matches = M.find_methods(word, class_part, root)
  if #matches == 0 then
    -- Try searching if word is Class:method or Class.method
    if word:find('[:.]') then
      local cls, mth = word:match('^([%w_]+)[:.]([%w_]+)$')
      if mth then
        matches = M.find_methods(mth, cls, root)
      end
    end
  end

  if #matches == 0 then
    return false
  end

  if #matches == 1 then
    local target = matches[1]
    vim.cmd('edit ' .. vim.fn.fnameescape(target.file))
    vim.api.nvim_win_set_cursor(0, { target.line, math.max(target.col or 0, 0) })
    vim.cmd('normal! zz')
    return true
  end

  -- Multiple matches: prompt user to select
  vim.ui.select(matches, {
    prompt = 'Select C++ luabind definition',
    format_item = function(item)
      return string.format('%s (%s:%d)', item.signature or item.name, vim.fs.basename(item.file), item.line)
    end,
  }, function(choice)
    if choice then
      vim.cmd('edit ' .. vim.fn.fnameescape(choice.file))
      vim.api.nvim_win_set_cursor(0, { choice.line, math.max(choice.col or 0, 0) })
      vim.cmd('normal! zz')
    end
  end)

  return true
end

-- Show hover popup for method under cursor
function M.show_hover(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local root = M.get_project_root(bufnr)
  if not M.has_luabind(root) then
    return false
  end

  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local word = vim.fn.expand('<cword>')
  if not word or word == '' then
    return false
  end

  local class_part = nil
  local before = line:sub(1, col + 1)
  local member_prefix = before:match('([%w_]+)[.:][%w_]*$')
  if member_prefix and member_prefix ~= word then
    class_part = member_prefix
  end

  local matches = M.find_methods(word, class_part, root)
  if #matches == 0 then
    return false
  end

  local docs = {}
  for idx, m in ipairs(matches) do
    if idx > 1 then
      table.insert(docs, '\n---\n')
    end
    table.insert(docs, M.format_documentation(m))
  end

  local full_text = table.concat(docs, '\n')
  local doc_lines = vim.split(full_text, '\n', { plain = true })

  vim.lsp.util.open_floating_preview(doc_lines, 'markdown', {
    border = 'rounded',
    focus_id = 'luabind_hover',
    focus = false,
  })

  return true
end

-- Generate Completion items for nvim-cmp
function M.get_cmp_items(params)
  local bufnr = (params and params.context and params.context.bufnr) or 0
  local root = (params and params.root) or M.get_project_root(bufnr)
  if not M.has_luabind(root) then
    return {}
  end

  local methods = M.get_methods(root)
  if #methods == 0 then
    return {}
  end

  local ok_cmp, cmp = pcall(require, 'cmp')
  local kind_method = ok_cmp and cmp.lsp.CompletionItemKind.Method or 2
  local kind_func = ok_cmp and cmp.lsp.CompletionItemKind.Function or 3

  -- Check if cursor is after ClassName: or ClassName.
  local cursor_before = params and params.context and params.context.cursor_before_line or ''
  local prefix_class = cursor_before:match('([%w_]+)[.:][%w_]*$')
  local lowered_prefix = prefix_class and prefix_class:lower() or nil

  local items = {}
  local seen = {}

  for _, m in ipairs(methods) do
    local is_class_member = m.class_name ~= nil
    local match_class = (not lowered_prefix) or (is_class_member and m.class_name:lower() == lowered_prefix)

    if match_class then
      local item_key = (m.class_name or '') .. '::' .. m.name
      if not seen[item_key] then
        seen[item_key] = true

        local detail_str = string.format('%s [C++ luabind]', m.signature or m.name)

        table.insert(items, {
          label = m.name,
          kind = is_class_member and kind_method or kind_func,
          detail = detail_str,
          documentation = {
            kind = 'markdown',
            value = M.format_documentation(m),
          },
          insertText = m.name,
        })

        -- If not after a dot/colon, also offer Class:method as a suggestion
        if not prefix_class and is_class_member then
          local full_label = m.class_name .. ':' .. m.name
          table.insert(items, {
            label = full_label,
            kind = kind_method,
            detail = detail_str,
            documentation = {
              kind = 'markdown',
              value = M.format_documentation(m),
            },
            insertText = full_label,
          })
        end
      end
    end
  end

  return items
end

-- Register nvim-cmp source for luabind
function M.register_cmp_source()
  local ok, cmp = pcall(require, 'cmp')
  if not ok then return end

  local source = {}

  function source:is_available()
    local ft = vim.bo.filetype
    if ft == 'lua' or ft == 'luabind' or M.is_luabind_buffer() then
      return M.has_luabind()
    end
    return false
  end

  function source:get_keyword_pattern()
    return [[\k\+]]
  end

  function source:complete(params, callback)
    local items = M.get_cmp_items(params)
    callback({ items = items, isIncomplete = false })
  end

  pcall(cmp.register_source, 'luabind', source)
end

-- Split C++ parameter string taking templates <...> into account
local function split_params(params_str)
  if not params_str or params_str == '' then return {} end
  local list = {}
  local current = {}
  local depth = 0
  for i = 1, #params_str do
    local ch = params_str:sub(i, i)
    if ch == '<' then
      depth = depth + 1
      table.insert(current, ch)
    elseif ch == '>' then
      if depth > 0 then depth = depth - 1 end
      table.insert(current, ch)
    elseif ch == ',' and depth == 0 then
      local s = vim.trim(table.concat(current))
      if s ~= '' then table.insert(list, s) end
      current = {}
    else
      table.insert(current, ch)
    end
  end
  local s = vim.trim(table.concat(current))
  if s ~= '' then table.insert(list, s) end
  return list
end

-- Parse cursor context to find if we are inside a function call
function M.parse_call_context(text_before)
  if not text_before or text_before == '' then
    return nil
  end

  local depth = 0
  local open_paren_idx = nil

  for i = #text_before, 1, -1 do
    local ch = text_before:sub(i, i)
    if ch == ')' then
      depth = depth + 1
    elseif ch == '(' then
      if depth > 0 then
        depth = depth - 1
      else
        open_paren_idx = i
        break
      end
    end
  end

  if not open_paren_idx then
    return nil
  end

  local param_idx = 1
  local comma_depth = 0
  for i = open_paren_idx + 1, #text_before do
    local ch = text_before:sub(i, i)
    if ch == '(' or ch == '<' or ch == '{' or ch == '[' then
      comma_depth = comma_depth + 1
    elseif ch == ')' or ch == '>' or ch == '}' or ch == ']' then
      if comma_depth > 0 then
        comma_depth = comma_depth - 1
      end
    elseif ch == ',' and comma_depth == 0 then
      param_idx = param_idx + 1
    end
  end

  local before_paren = text_before:sub(1, open_paren_idx - 1)
  local class_name, func_name = before_paren:match('([%w_]+)[.:]([%w_]+)%s*$')
  if not func_name then
    func_name = before_paren:match('([%w_]+)%s*$')
  end

  if not func_name then
    return nil
  end

  return {
    class_name = class_name,
    func_name = func_name,
    param_idx = param_idx,
  }
end

-- Format call hint lines with active parameter and method body comments
function M.format_call_hint(method, param_idx)
  local lines = {}
  table.insert(lines, '```cpp')
  table.insert(lines, method.signature or method.name)
  table.insert(lines, '```')

  local param_list = split_params(method.params)
  if #param_list > 0 then
    if param_idx >= 1 and param_idx <= #param_list then
      table.insert(lines, string.format('👉 **参数 (%d/%d):** `%s`', param_idx, #param_list, param_list[param_idx]))
    else
      table.insert(lines, string.format('⚠️ **输入参数超出声明范围 (第 %d 个)**', param_idx))
    end
  end

  if method.body_comments and #method.body_comments > 0 then
    table.insert(lines, '💡 **方法体注释：**')
    for _, c in ipairs(method.body_comments) do
      table.insert(lines, '* ' .. c)
    end
  end

  if method.doc_comments and #method.doc_comments > 0 then
    table.insert(lines, '📖 **说明：**')
    for _, c in ipairs(method.doc_comments) do
      table.insert(lines, '* ' .. c)
    end
  end

  return lines
end

-- Floating call hint window state
local active_hint_win = nil
local active_hint_buf = nil

function M.close_call_hint()
  if active_hint_win and vim.api.nvim_win_is_valid(active_hint_win) then
    pcall(vim.api.nvim_win_close, active_hint_win, true)
  end
  if active_hint_buf and vim.api.nvim_buf_is_valid(active_hint_buf) then
    pcall(vim.api.nvim_buf_delete, active_hint_buf, { force = true })
  end
  active_hint_win = nil
  active_hint_buf = nil
end

function M.show_call_hint(info, bufnr)
  local method = info.method
  local param_idx = info.param_idx or 1
  local lines = M.format_call_hint(method, param_idx)

  local max_w = 70
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, #l)
  end
  width = math.min(math.max(width + 2, 20), max_w)
  local height = math.min(#lines, 14)

  if active_hint_win and vim.api.nvim_win_is_valid(active_hint_win) and active_hint_buf and vim.api.nvim_buf_is_valid(active_hint_buf) then
    vim.api.nvim_buf_set_lines(active_hint_buf, 0, -1, false, lines)
    pcall(vim.api.nvim_win_set_config, active_hint_win, {
      width = width,
      height = height,
    })
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local cursor_win = vim.api.nvim_get_current_win()
  local cursor_row = vim.api.nvim_win_get_cursor(cursor_win)[1]
  local win_top = vim.fn.line('w0')
  local space_above = cursor_row - win_top

  local row = 1
  if space_above >= height + 1 then
    row = -(height + 2)
  end

  local win_opts = {
    relative = 'cursor',
    row = row,
    col = 0,
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    focusable = false,
    zindex = 45,
  }

  local ok, win = pcall(vim.api.nvim_open_win, buf, false, win_opts)
  if ok and win and vim.api.nvim_win_is_valid(win) then
    active_hint_win = win
    active_hint_buf = buf
  end
end

-- Insert mode hint updater
function M.update_insert_hint(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    M.close_call_hint()
    return
  end

  local root = M.get_project_root(bufnr)
  if not M.has_luabind(root) then
    M.close_call_hint()
    return
  end

  -- Don't show call hint if cmp menu is visible or popup menu is active
  if vim.fn.pumvisible() == 1 then
    M.close_call_hint()
    return
  end
  local ok_cmp, cmp = pcall(require, 'cmp')
  if ok_cmp and cmp.core and cmp.core.view and cmp.core.view:visible() then
    M.close_call_hint()
    return
  end

  local ok_line, line = pcall(vim.api.nvim_get_current_line)
  if not ok_line or not line then
    M.close_call_hint()
    return
  end
  local ok_cur, cur = pcall(vim.api.nvim_win_get_cursor, 0)
  if not ok_cur or not cur then
    M.close_call_hint()
    return
  end
  local col = cur[2]
  local text_before = line:sub(1, col)

  local ctx = M.parse_call_context(text_before)
  if not ctx then
    M.close_call_hint()
    return
  end

  local matches = M.find_methods(ctx.func_name, ctx.class_name, root)
  if #matches == 0 then
    M.close_call_hint()
    return
  end

  M.show_call_hint({
    method = matches[1],
    param_idx = ctx.param_idx,
  }, bufnr)
end

-- LSP SignatureHelp result for luabind
function M.get_signature_help(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local root = M.get_project_root(bufnr)
  if not M.has_luabind(root) then
    return nil
  end

  local ok_line, line = pcall(vim.api.nvim_get_current_line)
  if not ok_line or not line then
    return nil
  end
  local ok_cur, cur = pcall(vim.api.nvim_win_get_cursor, 0)
  if not ok_cur or not cur then
    return nil
  end
  local col = cur[2]
  local text_before = line:sub(1, col)

  local ctx = M.parse_call_context(text_before)
  if not ctx then
    return nil
  end

  local matches = M.find_methods(ctx.func_name, ctx.class_name, root)
  if #matches == 0 then
    return nil
  end

  local m = matches[1]
  local param_list = split_params(m.params)
  local parameters = {}
  for _, p in ipairs(param_list) do
    table.insert(parameters, { label = p })
  end

  local doc_lines = M.format_call_hint(m, ctx.param_idx)

  return {
    signatures = {
      {
        label = m.signature or m.name,
        documentation = {
          kind = 'markdown',
          value = table.concat(doc_lines, '\n'),
        },
        parameters = parameters,
        activeParameter = math.max((ctx.param_idx or 1) - 1, 0),
      },
    },
    activeSignature = 0,
    activeParameter = math.max((ctx.param_idx or 1) - 1, 0),
  }
end

-- Generate LuaCATS / EmmyLua definitions file for lua_ls
function M.generate_meta_file(root)
  root = M.get_project_root(root)
  if not M.has_luabind(root) then
    return nil
  end

  local methods = M.get_methods(root)
  local cache_dir = vim.fs.joinpath(vim.fn.stdpath('cache'), 'luabind', vim.fn.sha256(root))
  vim.fn.mkdir(cache_dir, 'p')
  local meta_file = vim.fs.joinpath(cache_dir, 'luabind_meta.lua')

  local lines = {
    '---@meta',
    '-- Auto-generated LuaCATS definitions from .luabind C++ bindings',
    '',
  }

  local classes = {}
  for _, m in ipairs(methods) do
    if m.class_name then
      classes[m.class_name] = true
    end
  end

  for class_name in pairs(classes) do
    table.insert(lines, string.format('---@class %s', class_name))
    table.insert(lines, string.format('%s = {}', class_name))
    table.insert(lines, '')
  end

  for _, m in ipairs(methods) do
    -- Comments
    if m.doc_comments and #m.doc_comments > 0 then
      for _, c in ipairs(m.doc_comments) do
        table.insert(lines, '--- ' .. c)
      end
    end
    if m.body_comments and #m.body_comments > 0 then
      for _, c in ipairs(m.body_comments) do
        table.insert(lines, '--- ' .. c)
      end
    end

    local fn_decl
    if m.class_name then
      fn_decl = string.format('function %s:%s(%s) end', m.class_name, m.name, m.params or '')
    else
      fn_decl = string.format('function %s(%s) end', m.name, m.params or '')
    end
    table.insert(lines, fn_decl)
    table.insert(lines, '')
  end

  pcall(vim.fn.writefile, lines, meta_file)
  return cache_dir
end

-- Configure lua_ls workspace library
function M.setup_lua_ls_workspace(new_config, new_root_dir)
  local root = new_root_dir or M.get_project_root(0)
  if not M.has_luabind(root) then
    return
  end

  local meta_dir = M.generate_meta_file(root)
  if meta_dir and new_config.settings and new_config.settings.Lua then
    new_config.settings.Lua.workspace = new_config.settings.Lua.workspace or {}
    new_config.settings.Lua.workspace.library = new_config.settings.Lua.workspace.library or {}
    table.insert(new_config.settings.Lua.workspace.library, meta_dir)
  end
end

-- Attach buffer-local luabind mappings and helpers
function M.attach_to_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local ft = vim.bo[bufnr].filetype
  local is_lua = (ft == 'lua')
  local is_luabind = (ft == 'luabind') or M.is_luabind_buffer(bufnr)
  if not is_lua and not is_luabind then
    return
  end

  local root = M.get_project_root(bufnr)
  if not M.has_luabind(root) then
    return
  end

  -- Ensure methods are loaded
  M.get_methods(root)

  local function safe_jump()
    local handled = M.jump_to_definition({ bufnr = bufnr })
    if not handled then
      vim.lsp.buf.definition()
    end
  end

  local function safe_hover()
    local handled = M.show_hover({ bufnr = bufnr })
    if not handled then
      vim.lsp.buf.hover()
    end
  end

  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, {
      buffer = bufnr,
      silent = true,
      desc = desc,
    })
  end

  map('n', '<C-]>', safe_jump, 'Go to Definition (with luabind)')
  map('n', 'gd', safe_jump, 'Go to Definition (with luabind)')
  map('n', '<leader>ld', safe_jump, 'LSP: Go to definition (with luabind)')
  map('n', 'K', safe_hover, 'Hover (with luabind)')
  map('n', '<leader>lh', safe_hover, 'LSP: Hover (with luabind)')

  -- Insert mode signature help / auto-hint floating window
  local group = vim.api.nvim_create_augroup('LuabindHint_' .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd({ 'TextChangedI', 'CursorMovedI' }, {
    group = group,
    buffer = bufnr,
    callback = function()
      M.update_insert_hint(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    buffer = bufnr,
    callback = function()
      M.close_call_hint()
    end,
  })
end

function M.setup()
  M.register_cmp_source()

  vim.api.nvim_create_autocmd({ 'FileType', 'BufEnter', 'BufReadPost' }, {
    callback = function(args)
      local bufnr = args.buf
      if vim.api.nvim_buf_is_valid(bufnr) then
        local ft = vim.bo[bufnr].filetype
        if ft == 'lua' or ft == 'luabind' or M.is_luabind_buffer(bufnr) then
          M.attach_to_buffer(bufnr)
        end
      end
    end,
  })

  vim.api.nvim_create_user_command('LuabindReload', function()
    M.clear_cache()
    local root = M.get_project_root(0)
    local methods = M.get_methods(root)
    vim.notify(string.format('Reloaded luabind: found %d methods under %s', #methods, root), vim.log.levels.INFO)
  end, {
    desc = 'Reload .luabind definitions for current project',
  })

  vim.api.nvim_create_user_command('LuabindHover', function()
    M.show_hover({ bufnr = 0 })
  end, {
    desc = 'Show luabind hover hint',
  })
end

return M
