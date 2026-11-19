-- [[ user.telescope_ignore ]]
-- Conditional VCS (.gitignore) and .nvimignore command builder for Telescope find_files.

local M = {}

local DISABLE_VCS_DIRECTIVES = {
  ['no-vcs'] = true,
  ['no_vcs'] = true,
  ['novcs'] = true,
  ['no vcs'] = true,
  ['no-ignore-vcs'] = true,
  ['no_ignore_vcs'] = true,
  ['no ignore vcs'] = true,
  ['disable-vcs'] = true,
  ['disable_vcs'] = true,
  ['disable vcs'] = true,
  ['!vcs'] = true,
  ['vcs:false'] = true,
  ['vcs=false'] = true,
  ['vcs:off'] = true,
  ['vcs=off'] = true,
  ['use-vcs:false'] = true,
  ['use-vcs=false'] = true,
  ['use_vcs:false'] = true,
  ['use_vcs=false'] = true,
  ['use-vcs:off'] = true,
  ['use-vcs=off'] = true,
  ['use_vcs:off'] = true,
  ['use_vcs=off'] = true,
  ['不使用vcs'] = true,
  ['不使用 vcs'] = true,
  ['禁用vcs'] = true,
  ['禁用 vcs'] = true,
  ['关闭vcs'] = true,
  ['关闭 vcs'] = true,
}

local ENABLE_VCS_DIRECTIVES = {
  ['use-vcs'] = true,
  ['use_vcs'] = true,
  ['use vcs'] = true,
  ['vcs:true'] = true,
  ['vcs=true'] = true,
  ['vcs:on'] = true,
  ['vcs=on'] = true,
  ['use-vcs:true'] = true,
  ['use-vcs=true'] = true,
  ['use_vcs:true'] = true,
  ['use_vcs=true'] = true,
  ['use-vcs:on'] = true,
  ['use-vcs=on'] = true,
  ['use_vcs:on'] = true,
  ['use_vcs=on'] = true,
  ['使用vcs'] = true,
  ['使用 vcs'] = true,
  ['启用vcs'] = true,
  ['启用 vcs'] = true,
  ['开启vcs'] = true,
  ['开启 vcs'] = true,
}

local function normalize_comment_directive(line)
  local cleaned = tostring(line):gsub('^\239\187\191', ''):gsub('\r$', '')
  local trimmed = cleaned:match('^%s*(.-)%s*$')
  local body = trimmed:match('^#+%s*(.-)%s*$')
  if not body or body == '' then
    return nil
  end

  body = body:lower()
  body = body:gsub('^nvim%s*:%s*', '')
  body = body:gsub('^@%s*', '')
  body = body:gsub('%s*([:=])%s*', '%1')
  body = body:gsub('%s+', ' ')
  return body
end

--- Parse comment directives controlling whether VCS ignore files are applied.
---@param lines string[]|nil
---@return 'disable'|'enable'|nil
function M.parse_vcs_directive(lines)
  local directive = nil

  for _, line in ipairs(lines or {}) do
    local normalized = normalize_comment_directive(line)
    if normalized then
      if DISABLE_VCS_DIRECTIVES[normalized] then
        directive = 'disable'
      elseif ENABLE_VCS_DIRECTIVES[normalized] then
        directive = 'enable'
      end
    end
  end

  return directive
end

--- Read a .nvimignore file and parse any VCS comment directive.
---@param path string
---@return 'disable'|'enable'|nil
function M.read_vcs_directive(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= 'table' then
    return nil
  end

  return M.parse_vcs_directive(lines)
end

--- Collect existing .nvimignore files ordered from global config to project cwd.
---@param opts? { cwd?: string|false, config_dir?: string|false }
---@return string[]
function M.existing_ignore_files(opts)
  opts = opts or {}
  local uv = vim.uv or vim.loop
  local cwd = opts.cwd
  if cwd == nil then
    cwd = _G.initial_cwd or vim.fn.getcwd()
  end

  local config_dir = opts.config_dir
  if config_dir == nil then
    config_dir = vim.fn.stdpath('config')
  end

  local candidates = {}
  if type(config_dir) == 'string' and config_dir ~= '' then
    table.insert(candidates, vim.fs.joinpath(config_dir, '.nvimignore'))
  end
  if type(cwd) == 'string' and cwd ~= '' then
    table.insert(candidates, vim.fs.joinpath(cwd, '.nvimignore'))
  end

  local files = {}
  local seen = {}
  for _, path in ipairs(candidates) do
    local normalized = vim.fs.normalize(path)
    if not seen[normalized] then
      seen[normalized] = true
      local stat = uv.fs_stat(path)
      if stat and stat.type == 'file' then
        table.insert(files, path)
      end
    end
  end

  return files
end

--- Resolve active .nvimignore files and whether VCS ignore rules should be enabled.
---@param opts? { cwd?: string|false, config_dir?: string|false }
---@return { ignore_files: string[], use_vcs: boolean }
function M.resolve_ignore_config(opts)
  local ignore_files = M.existing_ignore_files(opts)
  local use_vcs = true

  for _, path in ipairs(ignore_files) do
    local directive = M.read_vcs_directive(path)
    if directive == 'disable' then
      use_vcs = false
    elseif directive == 'enable' then
      use_vcs = true
    end
  end

  return {
    ignore_files = ignore_files,
    use_vcs = use_vcs,
  }
end

--- Build the ripgrep command array for Telescope find_files.
---@param opts? { cwd?: string|false, config_dir?: string|false }
---@return string[]
function M.build_find_files_command(opts)
  local cfg = M.resolve_ignore_config(opts)
  local command = {
    'rg',
    '--files',
    '--hidden',
    '--follow',
    '--color',
    'never',
  }

  if cfg.use_vcs then
    table.insert(command, '--no-require-git')
  else
    vim.list_extend(command, {
      '--no-ignore-vcs',
      '--no-ignore-parent',
      '--no-ignore-dot',
      '--no-ignore-exclude',
      '--no-ignore-global',
    })
  end

  vim.list_extend(command, {
    '--glob',
    '!.git',
    '--glob',
    '!.git/**',
    '--glob',
    '!target',
    '--glob',
    '!target/**',
    '--glob',
    '!*.class',
  })

  for _, ignore_file in ipairs(cfg.ignore_files) do
    vim.list_extend(command, { '--ignore-file', ignore_file })
  end

  return command
end

return M
