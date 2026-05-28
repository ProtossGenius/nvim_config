local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
local json_meta = require('user.json_meta')

local function find_line_after(prefix, from_line)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for index = from_line, #lines do
    local line = lines[index]
    if vim.startswith(line, prefix) or vim.startswith(vim.trim(line), vim.trim(prefix)) then
      return index, line
    end
  end
  error('Could not find line with prefix: ' .. prefix)
end

local function find_line(prefix)
  return find_line_after(prefix, 1)
end

local temp_root = vim.fn.tempname()
vim.fn.mkdir(temp_root, 'p')
temp_root = vim.uv.fs_realpath(temp_root) or vim.fs.normalize(temp_root)

local schema_path = vim.fs.normalize(temp_root .. '/schema.json')
local target_path = vim.fs.normalize(temp_root .. '/config.json')

vim.fn.writefile(vim.split(vim.json.encode({
  title = 'Test Config',
  type = 'object',
  required = { 'configurations' },
  properties = {
    configurations = {
      type = 'array',
      items = {
        type = 'object',
        required = { 'name', 'enabled' },
        properties = {
          name = {
            type = 'string',
            description = 'Configuration name',
          },
          enabled = {
            type = 'boolean',
            description = 'Enable switch',
            default = false,
          },
          args = {
            type = 'json',
            description = 'Args list',
            default = {},
          },
        },
      },
    },
  },
}), '\n', { plain = true }), schema_path)

vim.fn.writefile(vim.split(vim.json.encode({
  configurations = {
    {
      name = 'alpha',
      enabled = true,
      args = { '--port', '8080' },
    },
  },
}), '\n', { plain = true }), target_path)

json_meta.open(target_path, schema_path, { split_cmd = 'botright 12split' })

local name_line = find_line('    name *: alpha')
support.expect_true('json meta renders name field', name_line > 0)

local args_line = find_line('    args: ["--port","8080"]')
vim.api.nvim_buf_set_lines(0, args_line - 1, args_line, false, { '    args: ["--port","9090"]' })

local header_line = find_line('- item 1')
vim.api.nvim_win_set_cursor(0, { header_line, 0 })
support.feed('=')
support.expect_true('json meta inserts array item below', find_line('- item 2') ~= nil)

local second_header_line = find_line_after('- item 2', header_line)
local second_name_line = find_line_after('    name *: ', second_header_line)
vim.api.nvim_buf_set_lines(0, second_name_line - 1, second_name_line, false, { '    name *: beta' })
local second_enabled_line = find_line_after('    enabled *: false', second_header_line)
vim.api.nvim_buf_set_lines(0, second_enabled_line - 1, second_enabled_line, false, { '    enabled *: true' })

local second_args_line = find_line_after('    args: ', second_header_line)
vim.api.nvim_win_set_cursor(0, { second_args_line, 0 })
support.feed('dd')
second_args_line = find_line_after('    args: ', second_header_line)
local cleared_args_line = vim.api.nvim_buf_get_lines(0, second_args_line - 1, second_args_line, false)[1]
support.expect_equal('json meta dd clears value but keeps key', cleared_args_line, '    args: ' )
vim.api.nvim_buf_set_lines(0, second_args_line - 1, second_args_line, false, { '    args: ["--beta"]' })

vim.cmd('write')

local saved = vim.json.decode(table.concat(vim.fn.readfile(target_path), '\n'))
support.expect_equal('json meta saves json values with type', saved.configurations[1].args[2], '9090')
support.expect_equal('json meta saves inserted array item', saved.configurations[2].name, 'beta')
support.expect_equal('json meta saves boolean values with type', saved.configurations[2].enabled, true)
support.expect_equal('json meta saves cleared and rewritten optional field', saved.configurations[2].args[1], '--beta')

vim.cmd('bdelete!')
vim.fn.delete(temp_root, 'rf')

support.flush()
