local M = {}

local function escape_tag_pattern(tag)
  return tag:gsub('([\\/])', '\\%1')
end

local function collect_help_files(dir)
  return vim.fs.find(function(name)
    return name:match('%.txt$') ~= nil
  end, { path = dir, type = 'file', limit = math.huge })
end

local function fallback_gen_tags(dir, include_index_tag)
  if dir == vim.NIL then
    dir = nil
  end
  if not dir or vim.fn.isdirectory(dir) == 0 then
    return
  end

  local tags = {}
  for _, file in ipairs(collect_help_files(dir)) do
    local relpath = vim.fs.relpath(dir, file) or vim.fs.basename(file)
    local ok, lines = pcall(vim.fn.readfile, file)
    if ok then
      for _, line in ipairs(lines) do
        for tag in line:gmatch('%*([^%s%*|][^%*|]-)%*') do
          table.insert(tags, ('%s\t%s\t/*%s*'):format(tag, relpath, escape_tag_pattern(tag)))
        end
      end
    end
  end

  if include_index_tag then
    table.insert(tags, ('help-tags\t%s\t1'):format('tags'))
  end

  tags = vim.fn.sort(tags)
  local out = io.open(vim.fs.joinpath(dir, 'tags'), 'w')
  if not out then
    return
  end
  for _, tag in ipairs(tags) do
    out:write(tag, '\n')
  end
  out:close()
end

local function patch_helptags_without_vimdoc_parser()
  local ok, help = pcall(require, 'vim._core.help')
  if not ok or type(help.gen_tags) ~= 'function' then
    return
  end

  local original_gen_tags = help.gen_tags
  help.gen_tags = function(...)
    local ok_gen, result = pcall(original_gen_tags, ...)
    if ok_gen then
      return result
    end

    local err = tostring(result)
    if err:find('No parser for language "vimdoc"', 1, true) then
      return fallback_gen_tags(...)
    end

    error(result)
  end
end

local function patch_position_params_default_encoding()
  if not (vim.lsp and vim.lsp.util and type(vim.lsp.util.make_position_params) == 'function') then
    return
  end

  local original_make_position_params = vim.lsp.util.make_position_params
  vim.lsp.util.make_position_params = function(win, position_encoding)
    if position_encoding == nil then
      local bufnr = vim.api.nvim_win_get_buf(win or 0)
      local client = vim.lsp.get_clients({ bufnr = bufnr })[1]
      position_encoding = client and client.offset_encoding or 'utf-16'
    end

    return original_make_position_params(win, position_encoding)
  end
end

function M.setup()
  if not vim.tbl_islist and vim.islist then
    vim.tbl_islist = vim.islist
  end

  if vim.fn.has('nvim-0.12') == 1 then
    patch_helptags_without_vimdoc_parser()
    patch_position_params_default_encoding()
  end
end

return M
