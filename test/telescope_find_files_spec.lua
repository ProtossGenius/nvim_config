local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

local map = vim.fn.maparg('<C-p>', 'n', false, true)
support.expect_true('ctrl-p find files mapping has callback', type(map.callback) == 'function')

local ok, err = pcall(function()
  vim.defer_fn(function()
    pcall(require('telescope.actions').close, vim.api.nvim_get_current_buf())
  end, 200)
  map.callback()
  vim.wait(500)
end)

support.expect_true('ctrl-p find files opens without sync error', ok, err)

local telescope_ignore = require('user.telescope_ignore')

-- Unit tests for .nvimignore VCS comment directive parsing
local disable_samples = {
  '# no-vcs',
  '# NO-VCS',
  '# @no-vcs',
  '# nvim: no-vcs',
  '# !vcs',
  '# no-ignore-vcs',
  '# vcs: false',
  '# vcs=off',
  '# use-vcs: false',
  '# 不使用vcs',
  '# 不使用 vcs',
  '\239\187\191# no-vcs\r',
}

for _, line in ipairs(disable_samples) do
  support.expect_equal('parse disable directive: ' .. line, telescope_ignore.parse_vcs_directive({ line }), 'disable')
end

local enable_samples = {
  '# use-vcs',
  '# vcs: true',
  '# 使用vcs',
}

for _, line in ipairs(enable_samples) do
  support.expect_equal('parse enable directive: ' .. line, telescope_ignore.parse_vcs_directive({ line }), 'enable')
end

support.expect_equal(
  'ignore prose comment mentioning vcs',
  telescope_ignore.parse_vcs_directive({ '# ignore build artifacts not in vcs' }),
  nil
)
support.expect_equal('ignore non-comment line', telescope_ignore.parse_vcs_directive({ 'no-vcs' }), nil)
support.expect_equal('ignore empty lines', telescope_ignore.parse_vcs_directive({ '', '   ', '#' }), nil)
support.expect_equal(
  'later directive overrides earlier directive',
  telescope_ignore.parse_vcs_directive({ '# no-vcs', '# use-vcs' }),
  'enable'
)

-- Integration tests with real ripgrep execution in an isolated temp directory
local function has_flag(cmd, flag)
  return vim.tbl_contains(cmd, flag)
end

local function flag_values(cmd, flag)
  local values = {}
  for i = 1, #cmd - 1 do
    if cmd[i] == flag then
      table.insert(values, cmd[i + 1])
    end
  end
  return values
end

local function run_rg(cmd, cwd)
  local res = vim.system(cmd, { cwd = cwd, text = true }):wait()
  support.expect_equal('rg exit code in ' .. cwd, res.code, 0)
  local found = {}
  for line in (res.stdout or ''):gmatch('[^\r\n]+') do
    found[line] = true
  end
  return found
end

local tmp_root = vim.fn.tempname()
local proj_dir = vim.fs.joinpath(tmp_root, 'project')
local global_cfg_dir = vim.fs.joinpath(tmp_root, 'config')

local integration_ok, integration_err = pcall(function()
  vim.fn.mkdir(vim.fs.joinpath(proj_dir, 'build'), 'p')
  vim.fn.mkdir(vim.fs.joinpath(proj_dir, 'extra'), 'p')
  vim.fn.mkdir(vim.fs.joinpath(proj_dir, 'src'), 'p')
  vim.fn.mkdir(global_cfg_dir, 'p')

  vim.fn.writefile({ 'build/' }, vim.fs.joinpath(proj_dir, '.gitignore'))
  vim.fn.writefile({ 'build artifact' }, vim.fs.joinpath(proj_dir, 'build', 'out.txt'))
  vim.fn.writefile({ 'extra artifact' }, vim.fs.joinpath(proj_dir, 'extra', 'nvim_ignored.txt'))
  vim.fn.writefile({ 'int main() { return 0; }' }, vim.fs.joinpath(proj_dir, 'src', 'main.cpp'))

  local proj_nvimignore = vim.fs.joinpath(proj_dir, '.nvimignore')
  local global_nvimignore = vim.fs.joinpath(global_cfg_dir, '.nvimignore')

  -- Case 1a: no .nvimignore and no .git directory -> uses .gitignore via --no-require-git
  local cfg1 = telescope_ignore.resolve_ignore_config({ cwd = proj_dir, config_dir = false })
  support.expect_equal('case1 use_vcs is true without .nvimignore', cfg1.use_vcs, true)
  support.expect_equal('case1 ignore_files empty without .nvimignore', cfg1.ignore_files, {})

  local cmd1 = telescope_ignore.build_find_files_command({ cwd = proj_dir, config_dir = false })
  support.expect_true('case1 has --no-require-git', has_flag(cmd1, '--no-require-git'))
  support.expect_true('case1 lacks --no-ignore-vcs', not has_flag(cmd1, '--no-ignore-vcs'))
  support.expect_equal('case1 lacks --ignore-file', flag_values(cmd1, '--ignore-file'), {})

  local files1a = run_rg(cmd1, proj_dir)
  support.expect_true('case1a finds src/main.cpp', files1a['src/main.cpp'] == true)
  support.expect_true('case1a finds extra/nvim_ignored.txt', files1a['extra/nvim_ignored.txt'] == true)
  support.expect_true('case1a excludes build/out.txt without .git', files1a['build/out.txt'] == nil)

  -- Case 1b: no .nvimignore with .git directory present -> excludes .git and build/
  vim.fn.mkdir(vim.fs.joinpath(proj_dir, '.git'), 'p')
  vim.fn.writefile({ 'ref: refs/heads/main' }, vim.fs.joinpath(proj_dir, '.git', 'HEAD'))
  local files1b = run_rg(cmd1, proj_dir)
  support.expect_true('case1b finds src/main.cpp', files1b['src/main.cpp'] == true)
  support.expect_true('case1b excludes build/out.txt with .git', files1b['build/out.txt'] == nil)
  support.expect_true('case1b excludes .git/HEAD', files1b['.git/HEAD'] == nil)

  -- Case 2: .nvimignore without no-vcs -> combines VCS (.gitignore) + .nvimignore
  vim.fn.writefile({ 'extra/' }, proj_nvimignore)
  local cfg2 = telescope_ignore.resolve_ignore_config({ cwd = proj_dir, config_dir = false })
  support.expect_equal('case2 use_vcs stays true', cfg2.use_vcs, true)
  support.expect_equal('case2 ignore_files has project .nvimignore', cfg2.ignore_files, { proj_nvimignore })

  local cmd2 = telescope_ignore.build_find_files_command({ cwd = proj_dir, config_dir = false })
  support.expect_true('case2 has --no-require-git', has_flag(cmd2, '--no-require-git'))
  support.expect_true('case2 lacks --no-ignore-vcs', not has_flag(cmd2, '--no-ignore-vcs'))
  support.expect_equal('case2 --ignore-file', flag_values(cmd2, '--ignore-file'), { proj_nvimignore })

  local files2 = run_rg(cmd2, proj_dir)
  support.expect_true('case2 finds src/main.cpp', files2['src/main.cpp'] == true)
  support.expect_true('case2 excludes build/out.txt via .gitignore', files2['build/out.txt'] == nil)
  support.expect_true('case2 excludes extra/nvim_ignored.txt via .nvimignore', files2['extra/nvim_ignored.txt'] == nil)

  -- Case 3: .nvimignore with # no-vcs -> disables VCS, applies .nvimignore only
  vim.fn.writefile({ '# no-vcs', 'extra/' }, proj_nvimignore)
  local cfg3 = telescope_ignore.resolve_ignore_config({ cwd = proj_dir, config_dir = false })
  support.expect_equal('case3 use_vcs is false', cfg3.use_vcs, false)

  local cmd3 = telescope_ignore.build_find_files_command({ cwd = proj_dir, config_dir = false })
  support.expect_true('case3 lacks --no-require-git', not has_flag(cmd3, '--no-require-git'))
  for _, flag in ipairs({ '--no-ignore-vcs', '--no-ignore-parent', '--no-ignore-dot', '--no-ignore-exclude', '--no-ignore-global' }) do
    support.expect_true('case3 has ' .. flag, has_flag(cmd3, flag))
  end
  support.expect_equal('case3 --ignore-file', flag_values(cmd3, '--ignore-file'), { proj_nvimignore })

  local files3 = run_rg(cmd3, proj_dir)
  support.expect_true('case3 finds src/main.cpp', files3['src/main.cpp'] == true)
  support.expect_true('case3 finds build/out.txt when VCS disabled', files3['build/out.txt'] == true)
  support.expect_true('case3 excludes extra/nvim_ignored.txt', files3['extra/nvim_ignored.txt'] == nil)

  -- Case 4: .nvimignore with # 不使用vcs -> disables VCS, applies .nvimignore only
  vim.fn.writefile({ '# 不使用vcs', 'extra/' }, proj_nvimignore)
  local cfg4 = telescope_ignore.resolve_ignore_config({ cwd = proj_dir, config_dir = false })
  support.expect_equal('case4 use_vcs is false for Chinese directive', cfg4.use_vcs, false)

  local cmd4 = telescope_ignore.build_find_files_command({ cwd = proj_dir, config_dir = false })
  local files4 = run_rg(cmd4, proj_dir)
  support.expect_true('case4 finds src/main.cpp', files4['src/main.cpp'] == true)
  support.expect_true('case4 finds build/out.txt', files4['build/out.txt'] == true)
  support.expect_true('case4 excludes extra/nvim_ignored.txt', files4['extra/nvim_ignored.txt'] == nil)

  -- Case 5: global config_dir/.nvimignore + project cwd/.nvimignore precedence and deduplication
  vim.fn.writefile({ '# no-vcs' }, global_nvimignore)
  vim.fn.writefile({ 'extra/' }, proj_nvimignore)
  local cfg5a = telescope_ignore.resolve_ignore_config({ cwd = proj_dir, config_dir = global_cfg_dir })
  support.expect_equal('case5a global # no-vcs disables VCS', cfg5a.use_vcs, false)
  local cmd5a = telescope_ignore.build_find_files_command({ cwd = proj_dir, config_dir = global_cfg_dir })
  support.expect_equal(
    'case5a --ignore-file order is [global, project]',
    flag_values(cmd5a, '--ignore-file'),
    { global_nvimignore, proj_nvimignore }
  )

  vim.fn.writefile({ '# use-vcs', 'extra/' }, proj_nvimignore)
  local cfg5b = telescope_ignore.resolve_ignore_config({ cwd = proj_dir, config_dir = global_cfg_dir })
  support.expect_equal('case5b project # use-vcs overrides global # no-vcs', cfg5b.use_vcs, true)

  local cmd5c = telescope_ignore.build_find_files_command({ cwd = proj_dir, config_dir = proj_dir })
  support.expect_equal(
    'case5c deduplicates identical config_dir and cwd',
    flag_values(cmd5c, '--ignore-file'),
    { proj_nvimignore }
  )
end)

vim.fn.delete(tmp_root, 'rf')

if not integration_ok then
  error(integration_err, 0)
end

support.flush()
