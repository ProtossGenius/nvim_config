local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

local service_file = vim.fn.stdpath('config') .. '/test-projects/java17-spring-demo/core/src/main/java/com/example/demo/service/UserService.java'
local impl_file = vim.fn.stdpath('config') .. '/test-projects/java17-spring-demo/core/src/main/java/com/example/demo/service/impl/UserServiceImpl.java'

_G.initial_cwd = vim.fn.stdpath('config') .. '/test-projects/java17-spring-demo'
vim.cmd('cd ' .. vim.fn.fnameescape(_G.initial_cwd))

local function attach(path)
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  vim.bo.swapfile = false
  return vim.wait(60000, function()
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
      if client.name == 'jdtls' then
        return true
      end
    end
    return false
  end, 200)
end

local function request(method, line_nr, needle, offset, params_builder)
  local line = vim.api.nvim_buf_get_lines(0, line_nr - 1, line_nr, false)[1]
  local col = line:find(needle, 1, true) or 1
  vim.api.nvim_win_set_cursor(0, { line_nr, col - 1 + (offset or 0) })
  local done = false
  local err_out = nil
  local result_out = nil
  local params = params_builder and params_builder() or vim.lsp.util.make_position_params()
  vim.lsp.buf_request(0, method, params, function(err, result)
    err_out = err
    result_out = result
    done = true
  end)
  vim.wait(10000, function() return done end)
  return err_out, result_out
end

local function request_first(method, needle, offset, params_builder)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for idx, line in ipairs(lines) do
    if line:find(needle, 1, true) then
      return request(method, idx, needle, offset, params_builder)
    end
  end
  return { message = 'needle not found: ' .. needle }, nil
end

support.expect_true('java service navigation client attached for service', attach(service_file))

local err, result = request_first('textDocument/implementation', 'listUsers', 2)
support.expect_true('java service interface implementation succeeds', err == nil)
local impl_uri = result and result[1] and result[1].uri or ''
support.expect_true('java service interface implementation opens impl', impl_uri:find('UserServiceImpl%.java', 1) ~= nil)

err, result = request_first('textDocument/references', 'listUsers', 2, function()
  local params = vim.lsp.util.make_position_params()
  params.context = { includeDeclaration = true }
  return params
end)
support.expect_true('java service references succeeds', err == nil)
support.expect_true('java service references returns multiple locations', type(result) == 'table' and #result >= 3)

support.expect_true('java service navigation client attached for impl', attach(impl_file))

err, result = request_first('textDocument/declaration', 'listUsers', 2)
support.expect_true('java impl declaration succeeds', err == nil)
local decl_uri = result and result[1] and result[1].uri or ''
support.expect_true('java impl declaration opens service interface', decl_uri:find('UserService%.java', 1) ~= nil)

err, result = request_first('textDocument/implementation', 'listUsers', 2)
support.expect_true('java impl implementation succeeds', err == nil)
local self_uri = result and result[1] and result[1].uri or ''
support.expect_true('java impl implementation remains on impl', self_uri:find('UserServiceImpl%.java', 1) ~= nil)

vim.cmd('bdelete!')
support.flush()
