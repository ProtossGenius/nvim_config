-- [[ user.telescope_path ]]
-- Helper functions for Telescope path shortening to avoid filename truncation

local M = {}

local function parse_components(path, matched_indices)
  local components = {}
  local index_map = {}
  for _, idx in ipairs(matched_indices) do
    index_map[idx] = true
  end

  local start_pos = 1
  while start_pos <= #path do
    local end_pos = path:find("/", start_pos, true)
    local text
    local has_slash = false
    if end_pos then
      text = path:sub(start_pos, end_pos - 1)
      has_slash = true
    else
      text = path:sub(start_pos)
      end_pos = #path
    end

    local comp_start = start_pos
    local comp_end = end_pos - (has_slash and 1 or 0)

    local is_matched = false
    local comp_matched_indices = {}
    if comp_start <= comp_end then
      for i = comp_start, comp_end do
        if index_map[i] then
          is_matched = true
          table.insert(comp_matched_indices, i)
        end
      end
    end

    table.insert(components, {
      text = text,
      start_idx = comp_start,
      end_idx = comp_end,
      matched = is_matched,
      matched_indices = comp_matched_indices,
      has_slash = has_slash,
    })

    if has_slash then
      start_pos = end_pos + 1
    else
      break
    end
  end

  return components
end

local function get_filename_candidates(filename, filename_start_idx, index_map)
  local candidates = {}
  table.insert(candidates, filename)

  for i = 2, #filename do
    local char = filename:sub(i, i)
    local prev_char = filename:sub(i-1, i-1)
    local is_boundary = false
    if char:match("%u") then
      is_boundary = true
    elseif prev_char:match("[%s%-_%.%/]") then
      is_boundary = true
    end

    if is_boundary then
      local suffix = filename:sub(i)
      local covers_all_matches = true
      for idx, _ in pairs(index_map) do
        if idx >= filename_start_idx then
          local rel_idx = idx - filename_start_idx + 1
          if rel_idx < i then
            covers_all_matches = false
            break
          end
        end
      end

      if covers_all_matches then
        table.insert(candidates, suffix)
      end
    end
  end

  table.sort(candidates, function(a, b) return #a < #b end)
  return candidates
end

local function build_path(path, components, last_matched_idx, m, filename_candidate, index_map)
  local prefix_end_idx = (last_matched_idx > 0) and (last_matched_idx - 1) or (#components - 1)
  
  local abbr_components = {}
  local keep_components = {}
  
  for i = 1, prefix_end_idx do
    if i <= prefix_end_idx - m then
      table.insert(abbr_components, components[i])
    else
      table.insert(keep_components, components[i])
    end
  end
  
  local F = {}
  for _, comp in ipairs(abbr_components) do
    if not comp.matched then
      table.insert(F, "*")
    else
      local comp_str = ""
      local last_matched_pos = nil
      for idx = comp.start_idx, comp.end_idx do
        if index_map[idx] then
          if last_matched_pos then
            if idx > last_matched_pos + 1 then
              comp_str = comp_str .. "*"
            end
          else
            if idx > comp.start_idx then
              comp_str = comp_str .. "*"
            end
          end
          comp_str = comp_str .. path:sub(idx, idx)
          last_matched_pos = idx
        end
      end
      if last_matched_pos and last_matched_pos < comp.end_idx then
        comp_str = comp_str .. "*"
      end
      table.insert(F, comp_str)
    end
  end
  
  local parts = {}
  for i, val in ipairs(F) do
    if val == "*" then
      table.insert(parts, { text = "*", is_star = true })
    else
      local is_full = (val == abbr_components[i].text)
      table.insert(parts, { text = val, is_star = false, is_full = is_full })
    end
  end
  
  local collapsed = {}
  for _, p in ipairs(parts) do
    if p.is_star then
      if #collapsed == 0 or not collapsed[#collapsed].is_star then
        table.insert(collapsed, p)
      end
    else
      table.insert(collapsed, p)
    end
  end
  
  local prefix_str = ""
  for idx, p in ipairs(collapsed) do
    if idx == 1 then
      prefix_str = p.text
    else
      local prev = collapsed[idx - 1]
      if p.is_star then
        if not prev.is_star and prev.is_full then
          prefix_str = prefix_str .. "/*"
        else
          prefix_str = prefix_str .. "*"
        end
      else
        if p.is_full then
          prefix_str = prefix_str .. "/" .. p.text
        else
          if prev.is_star then
            prefix_str = prefix_str .. p.text
          else
            prefix_str = prefix_str .. "/" .. p.text
          end
        end
      end
    end
  end
  
  local keep_parts = {}
  for _, comp in ipairs(keep_components) do
    table.insert(keep_parts, comp.text)
  end
  
  if last_matched_idx > 0 then
    local last_comp = components[last_matched_idx]
    if last_matched_idx == #components then
      table.insert(keep_parts, filename_candidate)
    else
      table.insert(keep_parts, last_comp.text)
      for i = last_matched_idx + 1, #components - 1 do
        table.insert(keep_parts, components[i].text)
      end
      table.insert(keep_parts, filename_candidate)
    end
  else
    table.insert(keep_parts, filename_candidate)
  end
  
  local result = ""
  if prefix_str ~= "" then
    result = prefix_str
    if #keep_parts > 0 then
      result = result .. "/" .. table.concat(keep_parts, "/")
    end
  else
    result = table.concat(keep_parts, "/")
  end

  result = result:gsub("%*%*+", "*")
  return result
end

local function get_fuzzy_matched_indices(str, pattern)
  if not pattern or pattern == "" then
    return {}
  end
  local ok, res = pcall(vim.fn.matchfuzzypos, { str }, pattern)
  if ok and res and res[2] and res[2][1] then
    local indices = {}
    for _, idx in ipairs(res[2][1]) do
      table.insert(indices, idx + 1)
    end
    return indices
  end
  return {}
end

local function get_shortened_path_internal(path, query, max_len)
  if not path or path == "" then return "" end
  if not query or query == "" then
    if #path <= max_len then
      return path
    else
      local components = parse_components(path, {})
      local filename = components[#components].text
      local candidates = get_filename_candidates(filename, components[#components].start_idx, {})
      for _, cand in ipairs(candidates) do
        local test_path = path:sub(1, components[#components].start_idx - 1) .. cand
        if #test_path <= max_len then
          return test_path
        end
      end
      local test_path = "*/" .. candidates[1]
      if #test_path <= max_len then
        return test_path
      end
      return "*/" .. filename:sub(-max_len + 3)
    end
  end

  local matched_indices = get_fuzzy_matched_indices(path, query)
  if #matched_indices == 0 then
    if #path <= max_len then
      return path
    else
      local components = parse_components(path, {})
      local filename = components[#components].text
      return "*/" .. filename
    end
  end

  local index_map = {}
  for _, idx in ipairs(matched_indices) do
    index_map[idx] = true
  end

  local components = parse_components(path, matched_indices)
  
  local last_matched_idx = 0
  for i = #components, 1, -1 do
    if components[i].matched then
      last_matched_idx = i
      break
    end
  end

  local filename = components[#components].text
  local filename_start_idx = components[#components].start_idx
  local filename_candidates = get_filename_candidates(filename, filename_start_idx, index_map)

  local prefix_end_idx = (last_matched_idx > 0) and (last_matched_idx - 1) or (#components - 1)
  local max_m = prefix_end_idx

  local best_cand = nil
  for i = #filename_candidates, 1, -1 do
    local cand = filename_candidates[i]
    local test_path = build_path(path, components, last_matched_idx, 0, cand, index_map)
    if #test_path <= max_len then
      best_cand = cand
      break
    end
  end

  if not best_cand then
    best_cand = filename_candidates[1]
  end

  local best_path = build_path(path, components, last_matched_idx, 0, best_cand, index_map)
  for m = 1, max_m do
    local test_path = build_path(path, components, last_matched_idx, m, best_cand, index_map)
    if #test_path <= max_len then
      best_path = test_path
    else
      break
    end
  end

  return best_path
end

local function get_max_len(opts)
  local width = 80
  if opts and opts.picker and opts.picker.results_win then
    local win = opts.picker.results_win
    if vim.api.nvim_win_is_valid(win) then
      width = vim.api.nvim_win_get_width(win)
    end
  else
    local state = require('telescope.state')
    local prompt_bufnrs = state.get_existing_prompt_bufnrs()
    if prompt_bufnrs and prompt_bufnrs[1] then
      local action_state = require('telescope.actions.state')
      local picker = action_state.get_current_picker(prompt_bufnrs[1])
      if picker and picker.results_win and vim.api.nvim_win_is_valid(picker.results_win) then
        width = vim.api.nvim_win_get_width(picker.results_win)
      end
    end
  end
  local max_len = width - 15
  if max_len < 20 then
    max_len = 20
  end
  return max_len
end

function M.get_shortened_path(path, opts)
  local prompt = ""
  if opts and opts.picker then
    prompt = opts.picker:_get_prompt()
  else
    local state = require('telescope.state')
    local prompt_bufnrs = state.get_existing_prompt_bufnrs()
    if prompt_bufnrs and prompt_bufnrs[1] then
      local action_state = require('telescope.actions.state')
      local picker = action_state.get_current_picker(prompt_bufnrs[1])
      if picker then
        prompt = picker:_get_prompt()
      end
    end
  end
  local max_len = get_max_len(opts)
  return get_shortened_path_internal(path, prompt, max_len)
end

return M
