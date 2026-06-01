local M = {}

M.root_markers = {
  '.root',
  '.git',
  'mvnw',
  'gradlew',
  'pom.xml',
  'build.gradle',
  'build.gradle.kts',
  'settings.gradle',
  'settings.gradle.kts',
  'CMakeLists.txt',
  'Makefile',
  'package.json',
}

local function normalize(path)
  if not path or path == '' then
    return nil
  end

  return vim.fs.normalize(path)
end

function M.path_from_buf(bufnr)
  bufnr = bufnr or 0
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name ~= '' then
    return normalize(name)
  end

  return normalize(vim.fn.getcwd())
end

function M.root(path_or_bufnr)
  local start_path

  if type(path_or_bufnr) == 'number' then
    start_path = M.path_from_buf(path_or_bufnr)
  elseif type(path_or_bufnr) == 'string' then
    start_path = normalize(path_or_bufnr)
  else
    start_path = M.path_from_buf(0)
  end

  local base_path = start_path or vim.fn.getcwd()

  -- Prioritize .git and .root markers to find the true project root in monorepos/submodules
  local git_root = vim.fs.root(base_path, { '.git', '.root' })
  if git_root then
    return git_root
  end

  return vim.fs.root(base_path, M.root_markers) or vim.fn.getcwd()
end

function M.relative(path, root)
  local normalized_path = normalize(path)
  local normalized_root = normalize(root or M.root(path))
  if not normalized_path or not normalized_root then
    return path
  end

  local escaped_root = vim.pesc(normalized_root .. '/')
  local relative = normalized_path:gsub('^' .. escaped_root, '', 1)
  if relative ~= normalized_path then
    return relative
  end

  if normalized_path == normalized_root then
    return '.'
  end

  return normalized_path
end

function M.config_path(filename, path_or_bufnr)
  return vim.fs.joinpath(M.root(path_or_bufnr), filename)
end

function M.find_exact_file(name, opts)
  opts = opts or {}
  local root = normalize(opts.root or M.root(opts.path))
  local target = normalize(name)
  if not target or target == '' then
    return nil, 'Empty target.'
  end

  local stat = vim.uv.fs_stat(target)
  if stat and stat.type == 'file' then
    return target
  end

  if target:find('/', 1, true) or target:find('\\', 1, true) then
    local relative_path = root and normalize(vim.fs.joinpath(root, target)) or nil
    local relative_stat = relative_path and vim.uv.fs_stat(relative_path)
    if relative_stat and relative_stat.type == 'file' then
      return relative_path
    end
  end

  if not root then
    return nil, 'Could not resolve project root.'
  end

  local basename = vim.fs.basename(target)
  local matches = vim.fs.find(function(candidate)
    return candidate == basename
  end, {
    path = root,
    type = 'file',
    limit = opts.limit or 20,
  })

  if #matches == 0 then
    return nil, string.format('Could not find %s under %s.', basename, root)
  end

  if #matches > 1 then
    return nil, string.format('Found multiple exact matches for %s under %s.', basename, root)
  end

  return normalize(matches[1])
end

return M
