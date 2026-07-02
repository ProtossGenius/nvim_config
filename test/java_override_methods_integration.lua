local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

local source_root = vim.fs.joinpath(vim.fn.stdpath('config'), 'test-projects', 'java17-spring-demo', 'core')
local temp_root = vim.fn.tempname()
local project_root = temp_root .. '-project'
local file_path = vim.fs.joinpath(project_root, 'src', 'main', 'java', 'com', 'example', 'demo', 'service', 'impl', 'UserServiceImpl.java')

local function buf_lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function find_line(pattern)
  for index, line in ipairs(buf_lines()) do
    if line:find(pattern) then
      return index
    end
  end
end

local function has_error_diagnostic()
  for _, diagnostic in ipairs(vim.diagnostic.get(0)) do
    if diagnostic.severity == vim.diagnostic.severity.ERROR then
      return true
    end
  end
  return false
end

local function has_list_users_diagnostic()
  for _, diagnostic in ipairs(vim.diagnostic.get(0)) do
    local message = diagnostic.message or ''
    if message:find('listUsers', 1, true) and message:find('must implement', 1, true) then
      return true
    end
  end
  return false
end

local function remove_list_users_method(lines)
  local start_idx
  local end_idx

  for index, line in ipairs(lines) do
    if not start_idx and line:find('public List<User> listUsers%(%){?') then
      start_idx = index
      if index > 1 and lines[index - 1]:match('^%s*@Override%s*$') then
        start_idx = index - 1
      end
    end

    if start_idx and line:match('^  @Override$') and index > start_idx then
      end_idx = index - 1
      break
    end
  end

  support.expect_true(
    'java override integration found listUsers block',
    start_idx ~= nil and end_idx ~= nil and end_idx >= start_idx
  )

  local mutated = vim.deepcopy(lines)
  for _ = start_idx, end_idx do
    table.remove(mutated, start_idx)
  end
  return mutated
end

local copy_output = vim.fn.system({ 'cp', '-R', source_root, project_root })
support.expect_equal('java override demo copy succeeds', vim.v.shell_error, 0)

local original_lines = vim.fn.readfile(file_path)
local mutated_lines = remove_list_users_method(original_lines)
local original_ui_select = vim.ui.select
local user_select = require('user.select')
local original_select_many = user_select.select_many
local picked_prompt = false

local function restore()
  vim.ui.select = original_ui_select
  user_select.select_many = original_select_many
  vim.fn.writefile(original_lines, file_path)
  if vim.api.nvim_buf_is_valid(0) then
    vim.cmd('bdelete!')
  end
  vim.fn.delete(project_root, 'rf')
end

local ok, err = xpcall(function()
  vim.cmd('edit ' .. vim.fn.fnameescape(file_path))

  local attached = vim.wait(120000, function()
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
      if client.name == 'jdtls' then
        return true
      end
    end
    return false
  end, 200)
  support.expect_true('java override integration jdtls attached', attached)

  local clean = vim.wait(60000, function()
    return #vim.diagnostic.get(0) == 0
  end, 200)
  support.expect_true('java override integration file starts clean', clean)

  vim.api.nvim_buf_set_lines(0, 0, -1, false, mutated_lines)
  vim.cmd('write')

  local broken = vim.wait(60000, function()
    return has_list_users_diagnostic()
  end, 200)
  support.expect_true('java override integration delete shows listUsers error', broken)

  user_select.select_many = function(items, prompt, label_f, opts, on_choice)
    if prompt == 'Method to override' then
      local selected = {}
      for _, item in ipairs(items) do
        if item.name == 'listUsers' then
          table.insert(selected, item)
        end
      end
      picked_prompt = #selected == 1
      vim.schedule(function()
        on_choice(selected)
      end)
      return
    end

    return original_select_many(items, prompt, label_f, opts, on_choice)
  end

  local picked_from_vim_ui = false
  vim.ui.select = function(items, opts, on_choice)
    if opts and opts.prompt == 'Select methods to override.' then
      if not picked_from_vim_ui then
        picked_from_vim_ui = true
        for _, item in ipairs(items) do
          local value = item.value or item
          if value.name == 'listUsers' then
            vim.schedule(function()
              on_choice(item)
            end)
            return
          end
        end
      end

      vim.schedule(function()
        on_choice(nil)
      end)
      return
    end

    return original_ui_select(items, opts, on_choice)
  end

  local field_line = find_line('private final UserMapper userMapper;')
  local next_override_line = find_line('public User getUser%(')
  support.expect_true('java override integration found class body anchor', field_line ~= nil and next_override_line ~= nil)
  vim.api.nvim_win_set_cursor(0, { field_line + 1, 2 })

  local mapping = vim.fn.maparg('<leader>ji', 'n', false, true)
  support.expect_true('java override integration mapping exists', type(mapping.callback) == 'function')
  mapping.callback()

  local inserted = vim.wait(60000, function()
    return find_line('public List<User> listUsers%(%){?') ~= nil and not has_list_users_diagnostic()
  end, 200)
  support.expect_true('java override integration override inserts method', inserted)
  support.expect_true('java override integration selection prompt handled', picked_prompt or picked_from_vim_ui)

  local list_users_line = find_line('public List<User> listUsers%(%){?')
  local get_user_line = find_line('public User getUser%(')
  support.expect_true(
    'java override integration inserts method before getUser',
    list_users_line ~= nil and get_user_line ~= nil and list_users_line < get_user_line
  )
  support.expect_true('java override integration final errors cleared', not has_error_diagnostic())
end, debug.traceback)

restore()

if not ok then
  error(err .. '\ncopy output: ' .. tostring(copy_output))
end

support.flush()
