-- [[ user.java_class_search ]]
-- Telescope-based Java class/type search with:
-- 1. Fast in-memory & persistent disk caching for instant display.
-- 2. Subsequence fuzzy matching with custom case rule:
--    - Lowercase in pattern matches both lowercase and uppercase in target.
--    - Uppercase in pattern matches ONLY uppercase in target.
-- 3. Package search priority based on user selection history.
-- 4. Search history prefix-to-package associations with grey ghost text and Tab auto-completion.

local M = {}

-- Nerd Font icons
local ICON_PROJECT = '󰈙' -- project-local class file
local ICON_JAR     = '󰏗' -- JAR / third-party dependency class

-- LSP SymbolKind numbers that represent types
local TYPE_KINDS = {
  [vim.lsp.protocol.SymbolKind.Class]     = true,
  [vim.lsp.protocol.SymbolKind.Interface] = true,
  [vim.lsp.protocol.SymbolKind.Enum]      = true,
  [vim.lsp.protocol.SymbolKind.Struct]    = true,
}

-- In-memory cache and state
M._cache = {}
M._cache_set = {}
M._state = {
  package_priorities = {},
  prefix_associations = {},
}
M._state_loaded = false
M._ns = vim.api.nvim_create_namespace('user_java_class_search_ghost')

--- State file path in Neovim state directory
function M.get_state_file_path()
  local state_dir = vim.fn.stdpath('state')
  return vim.fs.normalize(vim.fs.joinpath(state_dir, 'java_class_search_state.json'))
end

--- Load persistent state from disk
function M.load_state()
  if M._state_loaded then
    return M._state
  end

  local file_path = M.get_state_file_path()
  local f = io.open(file_path, 'r')
  if f then
    local content = f:read('*a')
    f:close()
    if content and content ~= '' then
      local ok, decoded = pcall(vim.json.decode, content)
      if ok and type(decoded) == 'table' then
        M._state.package_priorities = decoded.package_priorities or {}
        M._state.prefix_associations = decoded.prefix_associations or {}
        if decoded.cached_classes and type(decoded.cached_classes) == 'table' then
          for _, item in ipairs(decoded.cached_classes) do
            M.add_to_cache(item, false)
          end
        end
      end
    end
  end

  M._state_loaded = true
  return M._state
end

--- Save persistent state to disk
function M.save_state()
  local file_path = M.get_state_file_path()
  local dir = vim.fs.dirname(file_path)
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end

  local cached_list = {}
  local limit = 3000 -- persist up to 3000 common/known classes
  for i = 1, math.min(#M._cache, limit) do
    local it = M._cache[i]
    table.insert(cached_list, {
      fqn = it.fqn,
      container = it.container,
      name = it.name,
      is_project = it.is_project,
      uri = it.uri,
      range = it.range,
      kind = it.kind,
    })
  end

  local data = {
    package_priorities = M._state.package_priorities,
    prefix_associations = M._state.prefix_associations,
    cached_classes = cached_list,
  }

  local ok, encoded = pcall(vim.json.encode, data)
  if ok and encoded then
    local f = io.open(file_path, 'w')
    if f then
      f:write(encoded)
      f:close()
    end
  end
end

--- Character matching rule:
--- - Lowercase in pattern can match both lowercase and uppercase in target.
--- - Uppercase in pattern can ONLY match uppercase in target.
--- - Non-alphabetical characters match exactly.
function M.char_matches(p_byte, t_byte)
  if p_byte == t_byte then
    return true
  end
  -- Lowercase [a-z] (97-122) can match uppercase [A-Z] (65-90)
  if p_byte >= 97 and p_byte <= 122 then
    if t_byte == p_byte - 32 then
      return true
    end
  end
  return false
end

--- Subsequence matching with custom casing rules.
--- Returns: matched (boolean), score (number), matched_indices (table)
function M.match_subsequence(pattern, target)
  if not pattern or pattern == '' then
    return true, 0, {}
  end
  if not target or target == '' then
    return false, 0, nil
  end

  local p_len = #pattern
  local t_len = #target
  if p_len > t_len then
    return false, 0, nil
  end

  local p_idx = 1
  local t_idx = 1
  local matched_indices = {}

  while p_idx <= p_len and t_idx <= t_len do
    local p_byte = pattern:byte(p_idx)
    local t_byte = target:byte(t_idx)
    if M.char_matches(p_byte, t_byte) then
      table.insert(matched_indices, t_idx)
      p_idx = p_idx + 1
    end
    t_idx = t_idx + 1
  end

  if p_idx <= p_len then
    return false, 0, nil
  end

  -- Calculate score:
  local score = 100
  local prev_idx = nil

  for _, idx in ipairs(matched_indices) do
    local is_boundary = false
    if idx == 1 then
      is_boundary = true
    else
      local prev_byte = target:byte(idx - 1)
      if prev_byte == 46 or prev_byte == 95 or prev_byte == 36 or prev_byte == 47 or prev_byte == 45 then
        is_boundary = true
      elseif prev_byte >= 97 and prev_byte <= 122 and target:byte(idx) >= 65 and target:byte(idx) <= 90 then
        is_boundary = true
      end
    end

    if is_boundary then
      score = score + 30
    end

    if prev_idx then
      if idx == prev_idx + 1 then
        score = score + 20 -- Consecutive bonus
      else
        score = score - math.min(idx - prev_idx - 1, 10)
      end
    end
    prev_idx = idx
  end

  return true, score, matched_indices
end

--- Calculate match score for an entry against user query and package priorities
function M.calculate_match(pattern, item, pkg_priorities)
  if not pattern or pattern == '' then
    local pkg = item.container or ''
    local p_score = (pkg_priorities and pkg_priorities[pkg]) or 0
    local proj_bonus = item.is_project and 200 or 0
    return true, p_score * 100 + proj_bonus
  end

  local fqn = item.fqn or item.name or ''
  local name = item.name or ''
  local pkg = item.container or ''

  local matches_name = false
  local name_score = 0
  if not pattern:find('%.', 1, true) then
    local ok, score = M.match_subsequence(pattern, name)
    if ok then
      matches_name = true
      name_score = score + 500 -- Direct class name match bonus
    end
  end

  local matches_fqn, fqn_score = M.match_subsequence(pattern, fqn)

  if not matches_name and not matches_fqn then
    return false, 0
  end

  local total_score = math.max(name_score, fqn_score)

  -- Package priority bonus
  local p_count = (pkg_priorities and pkg_priorities[pkg]) or 0
  total_score = total_score + p_count * 100

  -- Project file bonus
  if item.is_project then
    total_score = total_score + 200
  end

  return true, total_score
end

--- Determine whether a URI points to a project-local file or a dependency
local function is_project_uri(uri)
  if not uri then
    return false
  end

  if uri:sub(1, 6) == 'jdt://' then
    return false
  end

  if uri:sub(1, 7) == 'file://' then
    local path = vim.uri_to_fname(uri)
    local root = _G.initial_cwd or vim.fn.getcwd()
    root = vim.fs.normalize(root)
    path = vim.fs.normalize(path)
    return path:sub(1, #root) == root
  end

  return false
end

--- Add an item to cache safely without duplicates
function M.add_to_cache(item, save)
  local fqn = item.fqn
  if not fqn or fqn == '' then
    local container = item.container or item.containerName or ''
    local name = item.name or ''
    if container ~= '' then
      fqn = container .. '.' .. name
    else
      fqn = name
    end
    item.fqn = fqn
  end

  if not fqn or fqn == '' then
    return
  end

  if M._cache_set[fqn] then
    -- Update existing entry if needed
    local existing = M._cache_set[fqn]
    if item.uri and not existing.uri then
      existing.uri = item.uri
      existing.range = item.range
    end
    return
  end

  local entry = {
    fqn = fqn,
    container = item.container or item.containerName or '',
    name = item.name or (fqn:match('([%w_$]+)$') or fqn),
    is_project = item.is_project ~= nil and item.is_project or is_project_uri(item.uri),
    uri = item.uri,
    range = item.range,
    kind = item.kind or vim.lsp.protocol.SymbolKind.Class,
    raw = item.raw or item,
  }

  M._cache_set[fqn] = entry
  table.insert(M._cache, entry)

  if save then
    M.save_state()
  end
end

--- Fast local scan of project `.java` files
function M.scan_project_classes(root)
  root = root or _G.initial_cwd or vim.fn.getcwd()
  root = vim.fs.normalize(root)

  local function read_package(filepath)
    local f = io.open(filepath, 'r')
    if not f then
      return nil
    end
    local count = 0
    for line in f:lines() do
      count = count + 1
      if count > 40 then
        break
      end
      local pkg = line:match('^%s*package%s+([%w_%.]+)%s*;')
      if pkg then
        f:close()
        return pkg
      end
    end
    f:close()
    return nil
  end

  local java_files = vim.fs.find(function(name, path)
    return name:match('%.java$') ~= nil
  end, {
    path = root,
    type = 'file',
    limit = 2000,
  })

  for _, filepath in ipairs(java_files) do
    local filename = vim.fn.fnamemodify(filepath, ':t:r')
    local pkg = read_package(filepath) or ''
    local fqn = pkg ~= '' and (pkg .. '.' .. filename) or filename
    local uri = vim.uri_from_fname(filepath)

    M.add_to_cache({
      fqn = fqn,
      container = pkg,
      name = filename,
      is_project = true,
      uri = uri,
      range = {
        start = { line = 0, character = 0 },
        ['end'] = { line = 0, character = 0 },
      },
      kind = vim.lsp.protocol.SymbolKind.Class,
    }, false)
  end
end

--- Record user selection to boost package priority and establish prefix associations
function M.record_selection(query, item)
  if not item then
    return
  end
  M.load_state()

  local pkg = item.container or item.containerName or ''
  if pkg ~= '' then
    M._state.package_priorities[pkg] = (M._state.package_priorities[pkg] or 0) + 1
  end

  -- Record prefix association if query matched package
  query = vim.trim(query or '')
  if query ~= '' and pkg ~= '' then
    -- Check if query ends with dot or is used to match package
    local prefix = query:match('^(.-%.)') or query
    local clean_prefix = prefix:gsub('%.$', '')

    if M.match_subsequence(clean_prefix, pkg) or M.match_subsequence(prefix, pkg) then
      M._state.prefix_associations[prefix] = M._state.prefix_associations[prefix] or {}
      M._state.prefix_associations[prefix][pkg] = (M._state.prefix_associations[prefix][pkg] or 0) + 1

      if clean_prefix ~= prefix and clean_prefix ~= '' then
        M._state.prefix_associations[clean_prefix] = M._state.prefix_associations[clean_prefix] or {}
        M._state.prefix_associations[clean_prefix][pkg] = (M._state.prefix_associations[clean_prefix][pkg] or 0) + 1
      end
    end
  end

  M.save_state()
end

--- Get ghost suggestion for a query input
function M.get_prefix_suggestion(input)
  if not input or input == '' then
    return nil
  end
  M.load_state()

  -- 1. Check exact prefix key in associations
  local map = M._state.prefix_associations[input]
  if map then
    local best_pkg = nil
    local best_count = -1
    for pkg, count in pairs(map) do
      if count > best_count then
        best_pkg = pkg
        best_count = count
      end
    end
    if best_pkg then
      return best_pkg, best_count
    end
  end

  -- 2. Check if input matches recorded prefixes
  local best_pkg = nil
  local best_count = -1
  for prefix, pmap in pairs(M._state.prefix_associations) do
    if prefix:find(input, 1, true) == 1 or M.match_subsequence(input, prefix) then
      for pkg, count in pairs(pmap) do
        if count > best_count then
          best_pkg = pkg
          best_count = count
        end
      end
    end
  end

  if best_pkg then
    return best_pkg, best_count
  end

  -- 3. Check most used package matching input
  for pkg, count in pairs(M._state.package_priorities) do
    if M.match_subsequence(input, pkg) then
      if count > best_count then
        best_pkg = pkg
        best_count = count
      end
    end
  end

  return best_pkg, best_count
end

--- Filter all cached entries according to query and priority
function M.filter_entries(query, entries, pkg_priorities)
  entries = entries or M._cache
  pkg_priorities = pkg_priorities or (M.load_state() and M._state.package_priorities) or {}
  query = vim.trim(query or '')

  local results = {}

  for _, item in ipairs(entries) do
    local matched, score = M.calculate_match(query, item, pkg_priorities)
    if matched then
      table.insert(results, {
        item = item,
        score = score,
      })
    end
  end

  table.sort(results, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    if a.item.is_project ~= b.item.is_project then
      return a.item.is_project
    end
    return (a.item.fqn or '') < (b.item.fqn or '')
  end)

  local sorted_items = {}
  for _, r in ipairs(results) do
    table.insert(sorted_items, r.item)
  end

  return sorted_items
end

--- Convert LSP SymbolItem to our cache item structure
local function parse_lsp_symbol(item)
  local loc = item.location or {}
  local uri = loc.uri or loc.targetUri
  local range = loc.range or loc.targetRange
  local container = item.containerName or ''
  local name = item.name or ''
  local fqn = container ~= '' and (container .. '.' .. name) or name

  return {
    fqn = fqn,
    container = container,
    name = name,
    is_project = is_project_uri(uri),
    uri = uri,
    range = range,
    kind = item.kind,
    raw = item,
  }
end

--- Open the Telescope picker with live fuzzy search, ghost text, and instant display.
function M.search(opts)
  opts = opts or {}
  M.load_state()

  -- Pre-scan project classes if cache is small
  M.scan_project_classes()

  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local entry_display = require('telescope.pickers.entry_display')

  local clients = vim.lsp.get_clients({ name = 'jdtls' })
  local client = clients[1]
  local encoding = client and client.offset_encoding or 'utf-16'

  local displayer = entry_display.create({
    separator = ' ',
    items = {
      { width = 2 },
      { remaining = true },
    },
  })

  local make_display = function(entry)
    local item = entry.value
    local icon = item.is_project and ICON_PROJECT or ICON_JAR
    local hl = item.is_project and 'TelescopeResultsIdentifier' or 'TelescopeResultsComment'
    return displayer({
      { icon, hl },
      { item.fqn, 'TelescopeResultsNormal' },
    })
  end

  local current_picker_instance = nil
  local active_suggestion = nil
  local last_queried_prompt = ''
  local query_timer = nil

  local function cancel_timer()
    if query_timer then
      local t = query_timer
      query_timer = nil
      pcall(function()
        if not t:is_closing() then
          t:stop()
          t:close()
        end
      end)
    end
  end

  -- Dynamic finder that filters cache instantly and queries jdtls in background
  local finder = finders.new_dynamic({
    fn = function(prompt)
      prompt = prompt or ''
      local filtered = M.filter_entries(prompt, M._cache, M._state.package_priorities)

      -- Debounced background LSP query to enrich cache with new symbols from JARs
      if client and prompt ~= '' and prompt ~= last_queried_prompt then
        last_queried_prompt = prompt
        cancel_timer()
        query_timer = vim.defer_fn(function()
          query_timer = nil
          pcall(function()
            client:request('workspace/symbol', { query = prompt }, function(err, result)
              if not err and result and #result > 0 then
                local added = false
                for _, sym in ipairs(result) do
                  if TYPE_KINDS[sym.kind] then
                    local parsed = parse_lsp_symbol(sym)
                    if not M._cache_set[parsed.fqn] then
                      M.add_to_cache(parsed, false)
                      added = true
                    end
                  end
                end
                if added and current_picker_instance then
                  -- Refresh picker with newly discovered symbols
                  vim.schedule(function()
                    pcall(function()
                      local current_line = action_state.get_current_line()
                      if current_line == prompt then
                        current_picker_instance:refresh(finder, { reset_prompt = false })
                      end
                    end)
                  end)
                end
              end
            end, 0)
          end)
        end, 150)
      end

      local entries = {}
      for _, it in ipairs(filtered) do
        table.insert(entries, {
          value = it,
          display = make_display,
          ordinal = it.fqn,
        })
      end

      return entries
    end,
    entry_maker = function(entry)
      return entry
    end,
  })

  local picker = pickers.new(opts, {
    prompt_title = 'Java: Find Class (Project + JAR)',
    finder = finder,
    sorter = conf.generic_sorter(opts),
    previewer = false,
    attach_mappings = function(prompt_bufnr, map)
      current_picker_instance = action_state.get_current_picker(prompt_bufnr)

      -- Function to update grey ghost text in prompt buffer
      local function update_ghost_text()
        pcall(function()
          if not vim.api.nvim_buf_is_valid(prompt_bufnr) then
            return
          end
          local lines = vim.api.nvim_buf_get_lines(prompt_bufnr, 0, 1, false)
          local line_text = lines[1] or ''
          local prompt_prefix = conf.prompt_prefix or '> '
          local user_input = line_text
          if user_input:sub(1, #prompt_prefix) == prompt_prefix then
            user_input = user_input:sub(#prompt_prefix + 1)
          end
          user_input = vim.trim(user_input)

          vim.api.nvim_buf_clear_namespace(prompt_bufnr, M._ns, 0, -1)
          active_suggestion = nil

          if user_input ~= '' then
            local suggestion = M.get_prefix_suggestion(user_input)
            if suggestion and suggestion ~= user_input then
              active_suggestion = suggestion
              local hint = '  -> ' .. suggestion .. ' [Tab]'
              pcall(vim.api.nvim_buf_set_extmark, prompt_bufnr, M._ns, 0, #line_text, {
                virt_text = { { hint, 'Comment' } },
                virt_text_pos = 'eol',
                hl_mode = 'combine',
              })
            end
          end
        end)
      end

      -- Attach buffer listener for prompt updates
      vim.api.nvim_buf_attach(prompt_bufnr, false, {
        on_lines = function()
          vim.schedule(update_ghost_text)
        end,
        on_detach = function()
          cancel_timer()
        end,
      })

      -- Tab keymap: Apply ghost package prefix suggestion
      map('i', '<Tab>', function()
        if active_suggestion and active_suggestion ~= '' then
          local target_text = active_suggestion
          if target_text:sub(-1) ~= '.' then
            target_text = target_text .. '.'
          end

          local current_picker = action_state.get_current_picker(prompt_bufnr)
          if current_picker and current_picker.set_prompt then
            current_picker:set_prompt(target_text)
          else
            vim.api.nvim_buf_set_lines(prompt_bufnr, 0, -1, false, { target_text })
          end
          vim.schedule(update_ghost_text)
        else
          actions.move_selection_next(prompt_bufnr)
        end
      end)

      -- Select default action (<CR>)
      actions.select_default:replace(function()
        local current_prompt = action_state.get_current_line()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        if not selection or not selection.value then
          return
        end

        local item = selection.value
        M.record_selection(current_prompt, item)

        local uri = item.uri
        local range = item.range
        if uri and range then
          vim.lsp.util.jump_to_location({
            uri = uri,
            range = range,
          }, encoding, true)
        elseif uri then
          vim.lsp.util.jump_to_location({
            uri = uri,
            range = {
              start = { line = 0, character = 0 },
              ['end'] = { line = 0, character = 0 },
            },
          }, encoding, true)
        end
      end)

      return true
    end,
  })

  picker:find()
end

M._test = {
  char_matches = M.char_matches,
  match_subsequence = M.match_subsequence,
  calculate_match = M.calculate_match,
  record_selection = M.record_selection,
  get_prefix_suggestion = M.get_prefix_suggestion,
  filter_entries = M.filter_entries,
  add_to_cache = M.add_to_cache,
  scan_project_classes = M.scan_project_classes,
}

return M
