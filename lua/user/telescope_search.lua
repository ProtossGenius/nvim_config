local indexing = require('user.indexing')
local uv = vim.uv or vim.loop

local M = {}

local function append_ignore_file(files, path)
  local stat = path and uv.fs_stat(path) or nil
  if stat and stat.type == 'file' then
    table.insert(files, path)
  end
end

local function existing_ignore_files(cwd)
  local files = {}
  append_ignore_file(files, vim.fs.joinpath(vim.fn.stdpath('config'), '.nvimignore'))
  append_ignore_file(files, vim.fs.joinpath(cwd, '.nvimignore'))
  return files
end

local function configured_list(name, defaults)
  local value = vim.g[name]
  if type(value) == 'table' then
    return value
  end
  return defaults
end

local default_realtime_ignore_globs = {
  '!.git',
  '!.git/**',
  '!.cache',
  '!.cache/**',
  '!.local/share',
  '!.local/share/**',
  '!.m2/repository',
  '!.m2/repository/**',
  '!node_modules',
  '!node_modules/**',
  '!target',
  '!target/**',
  '!build',
  '!build/**',
  '!dist',
  '!dist/**',
  '!out',
  '!out/**',
  '!*.class',
}

local default_project_ignore_globs = {
  '!.git',
  '!.git/**',
  '!target',
  '!target/**',
  '!*.class',
}

local function add_globs(command, globs)
  for _, glob in ipairs(globs) do
    vim.list_extend(command, { '--glob', glob })
  end
end

local function add_ignore_files(command, cwd)
  for _, ignore_file in ipairs(existing_ignore_files(cwd)) do
    vim.list_extend(command, { '--ignore-file', ignore_file })
  end
end

local function base_find_command(cwd, realtime)
  local command = {
    'rg',
    '--files',
    '--hidden',
    '--color',
    'never',
    '--no-ignore-vcs',
    '--no-ignore-parent',
    '--no-ignore-dot',
    '--no-ignore-exclude',
  }

  if not realtime or vim.g.no_auto_index_follow_symlinks then
    table.insert(command, '--follow')
  end

  add_globs(command, configured_list(
    realtime and 'no_auto_index_ignore_globs' or 'project_search_ignore_globs',
    realtime and default_realtime_ignore_globs or default_project_ignore_globs
  ))
  add_ignore_files(command, cwd)

  return command
end

local function grep_extra_args(cwd, realtime)
  local args = {
    '--hidden',
  }

  if vim.g.no_auto_index_follow_symlinks then
    table.insert(args, '--follow')
  end

  add_globs(args, configured_list(
    realtime and 'no_auto_index_ignore_globs' or 'project_search_ignore_globs',
    realtime and default_realtime_ignore_globs or default_project_ignore_globs
  ))
  add_ignore_files(args, cwd)

  return args
end

local function prompt_len(prompt)
  prompt = vim.trim(prompt or '')
  return vim.fn.strchars(prompt)
end

local function glob_escape_char(char)
  if char:match('[%*%?%[%]%{%}%,%!\\]') then
    return '\\' .. char
  end
  return char
end

local function prompt_to_fuzzy_glob(prompt)
  prompt = vim.trim(prompt or '')
  if prompt == '' then
    return nil
  end

  local chars = {}
  for _, char in ipairs(vim.fn.split(prompt, '\\zs')) do
    if not char:match('%s') then
      table.insert(chars, glob_escape_char(char))
    end
  end

  if #chars == 0 then
    return nil
  end

  return '*' .. table.concat(chars, '*') .. '*'
end

local function realtime_find_files(opts)
  opts = opts or {}
  local cwd = indexing.search_cwd(opts)
  local min_chars = opts.min_chars or indexing.realtime_search_min_chars()
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local make_entry = require('telescope.make_entry')

  opts.cwd = cwd
  opts.entry_maker = opts.entry_maker or make_entry.gen_from_file(opts)

  pickers.new(opts, {
    prompt_title = string.format('Find Files (realtime, type >= %d chars)', min_chars),
    finder = finders.new_job(function(prompt)
      if prompt_len(prompt) < min_chars then
        return nil
      end

      local command = base_find_command(cwd, true)
      vim.list_extend(command, { '--iglob', prompt_to_fuzzy_glob(prompt) or '*' })
      return command
    end, opts.entry_maker, opts.max_results, cwd),
    previewer = conf.file_previewer(opts),
    sorter = conf.file_sorter(opts),
  }):find()
end

local function realtime_live_grep(opts)
  opts = opts or {}
  local cwd = indexing.search_cwd(opts)
  local min_chars = opts.min_chars or indexing.realtime_search_min_chars()
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local make_entry = require('telescope.make_entry')
  local conf = require('telescope.config').values
  local sorters = require('telescope.sorters')
  local vimgrep_arguments = vim.deepcopy(opts.vimgrep_arguments or conf.vimgrep_arguments)
  vim.list_extend(vimgrep_arguments, grep_extra_args(cwd, true))

  opts.cwd = cwd
  opts.entry_maker = opts.entry_maker or make_entry.gen_from_vimgrep(opts)

  pickers.new(opts, {
    prompt_title = string.format('Live Grep (realtime, type >= %d chars)', min_chars),
    finder = finders.new_job(function(prompt)
      if prompt_len(prompt) < min_chars then
        return nil
      end
      return vim.list_extend(vim.deepcopy(vimgrep_arguments), { '--', prompt })
    end, opts.entry_maker, opts.max_results, cwd),
    previewer = conf.grep_previewer(opts),
    sorter = sorters.highlighter_only(opts),
  }):find()
end

function M.find_all_files(opts)
  opts = opts or {}
  local cwd = indexing.search_cwd(opts)
  if indexing.is_no_auto_index_dir(cwd) then
    return realtime_find_files(vim.tbl_extend('force', opts, { cwd = cwd }))
  end

  return require('telescope.builtin').find_files(vim.tbl_extend('force', opts, {
    find_command = base_find_command(cwd, false),
    cwd = cwd,
  }))
end

function M.live_grep(opts)
  opts = opts or {}
  local cwd = indexing.search_cwd(opts)
  if indexing.is_no_auto_index_dir(cwd) then
    return realtime_live_grep(vim.tbl_extend('force', opts, { cwd = cwd }))
  end

  return require('telescope.builtin').live_grep(vim.tbl_extend('force', opts, {
    cwd = cwd,
    additional_args = function()
      return grep_extra_args(cwd, false)
    end,
  }))
end

function M.git_files(opts)
  opts = opts or {}
  local cwd = indexing.search_cwd(opts)
  if indexing.is_no_auto_index_dir(cwd) then
    return M.find_all_files(vim.tbl_extend('force', opts, { cwd = cwd }))
  end

  return require('telescope.builtin').git_files(vim.tbl_extend('force', opts, { cwd = cwd }))
end

M._test = {
  base_find_command = base_find_command,
  grep_extra_args = grep_extra_args,
  prompt_to_fuzzy_glob = prompt_to_fuzzy_glob,
  realtime_ignore_globs = default_realtime_ignore_globs,
}

return M
