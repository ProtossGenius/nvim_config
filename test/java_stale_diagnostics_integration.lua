local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

local source_root = vim.fs.joinpath(vim.fn.stdpath('config'), 'test-projects', 'java17-spring-demo', 'core')
local temp_root = vim.fn.tempname()
local project_root = temp_root .. '-project'
local file_path = vim.fs.joinpath(project_root, 'src', 'main', 'java', 'com', 'example', 'demo', 'service', 'impl', 'UserServiceImpl.java')

local function current_messages()
  local messages = {}
  for _, diagnostic in ipairs(vim.diagnostic.get(0)) do
    table.insert(messages, diagnostic.message)
  end
  table.sort(messages)
  return messages
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

local copy_output = vim.fn.system({ 'cp', '-R', source_root, project_root })
support.expect_equal('java stale diagnostics demo copy succeeds', vim.v.shell_error, 0)

local original_lines = vim.fn.readfile(file_path)

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
  support.expect_true('java stale diagnostics jdtls attached', attached)

  local clean = vim.wait(60000, function()
    return #vim.diagnostic.get(0) == 0
  end, 200)
  support.expect_true('java stale diagnostics file starts clean', clean)

  local start_idx
  local end_idx
  for index, line in ipairs(original_lines) do
    if not start_idx and line:find('public List<User> listUsers%(%){?') then
      start_idx = index
      if index > 1 and original_lines[index - 1]:match('^%s*@Override%s*$') then
        start_idx = index - 1
      end
    end
    if start_idx and line:match('^  @Override$') and index > start_idx then
      end_idx = index - 1
      break
    end
  end

  support.expect_true('java stale diagnostics found listUsers block', start_idx ~= nil and end_idx ~= nil and end_idx >= start_idx)

  local mutated = vim.deepcopy(original_lines)
  for _ = start_idx, end_idx do
    table.remove(mutated, start_idx)
  end

  vim.api.nvim_buf_set_lines(0, 0, -1, false, mutated)
  vim.cmd('write')

  local broken = vim.wait(60000, function()
    return has_list_users_diagnostic()
  end, 200)
  support.expect_true('java stale diagnostics delete shows listUsers error', broken)

  vim.api.nvim_buf_set_lines(0, 0, -1, false, original_lines)
  vim.cmd('write')

  local cleared = vim.wait(60000, function()
    return not has_list_users_diagnostic()
  end, 200)
  support.expect_true('java stale diagnostics restore clears listUsers error', cleared)
  support.expect_equal('java stale diagnostics restore leaves no diagnostics', current_messages(), {})
end, debug.traceback)

vim.fn.writefile(original_lines, file_path)
vim.cmd('bdelete!')
vim.fn.delete(project_root, 'rf')

if not ok then
  error(err .. '\ncopy output: ' .. tostring(copy_output))
end

support.flush()
