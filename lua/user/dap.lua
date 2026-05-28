local json_meta = require('user.json_meta')
local project = require('user.project')

local M = {}

local CONFIG_FILENAME = '.nvim-dap.json'

local config_schema = {
  title = 'DAP Configurations',
  description = 'Project-local debug configuration list.',
  type = 'object',
  required = { 'configurations' },
  properties = {
    configurations = {
      type = 'array',
      description = 'Available debug configurations for this project.',
      items = {
        type = 'object',
        required = { 'name', 'type', 'request' },
        properties = {
          name = {
            type = 'string',
            description = 'Display name shown in the debug picker.',
          },
          type = {
            type = 'string',
            description = 'DAP adapter id, for example java, go, python, cppdbg.',
          },
          request = {
            type = 'string',
            description = 'Usually launch or attach.',
            default = 'launch',
          },
          cwd = {
            type = 'string',
            description = 'Working directory. Supports ${projectRoot}, ${file}, ${fileDirname}.',
            default = '${projectRoot}',
          },
          program = {
            type = 'string',
            description = 'Program / script / binary path when the adapter expects one.',
          },
          mainClass = {
            type = 'string',
            description = 'Java main class when using java launch configs.',
          },
          modulePaths = {
            type = 'json',
            description = 'Optional JSON array/object value for adapter-specific module paths.',
            default = {},
          },
          classPaths = {
            type = 'json',
            description = 'Optional JSON array/object value for adapter-specific class paths.',
            default = {},
          },
          args = {
            type = 'json',
            description = 'JSON array or scalar args value, e.g. [\"--port\",\"8080\"].',
            default = {},
          },
          env = {
            type = 'json',
            description = 'JSON object of environment variables.',
            default = vim.empty_dict(),
          },
          stopOnEntry = {
            type = 'boolean',
            description = 'Stop immediately after launch.',
            default = false,
          },
          console = {
            type = 'string',
            description = 'Optional adapter-specific console setting.',
          },
        },
      },
    },
  },
}

local function config_path(path_or_bufnr)
  return project.config_path(CONFIG_FILENAME, path_or_bufnr)
end

local function decode_config(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return { configurations = {} }
  end

  local lines = vim.fn.readfile(path)
  if #lines == 0 then
    return { configurations = {} }
  end

  local ok, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not ok or type(decoded) ~= 'table' then
    error('Invalid DAP config JSON: ' .. path)
  end

  decoded.configurations = vim.islist(decoded.configurations) and decoded.configurations or {}
  return decoded
end

local function placeholder_vars()
  local path = project.path_from_buf(0) or ''
  local root = project.root(path)
  return {
    projectRoot = root,
    file = path,
    fileDirname = path ~= '' and vim.fn.fnamemodify(path, ':h') or root,
    fileBasename = path ~= '' and vim.fn.fnamemodify(path, ':t') or '',
    relativeFile = path ~= '' and project.relative(path, root) or '',
  }
end

local function expand_placeholders(value, vars)
  if type(value) == 'string' then
    return (value:gsub('%${([%w_]+)}', function(name)
      return vars[name] or '${' .. name .. '}'
    end))
  end

  if type(value) ~= 'table' then
    return value
  end

  local result = vim.islist(value) and {} or {}
  if vim.islist(value) then
    for index, item in ipairs(value) do
      result[index] = expand_placeholders(item, vars)
    end
    return result
  end

  for key, item in pairs(value) do
    result[key] = expand_placeholders(item, vars)
  end
  return result
end

local function normalize_config(config)
  local normalized = {}
  for key, value in pairs(config) do
    if key ~= 'name' and value ~= nil and not (type(value) == 'string' and value == '') then
      normalized[key] = value
    end
  end
  return normalized
end

local function prepare_java_dap()
  local ok, java = pcall(require, 'java')
  if ok and java.dap and java.dap.config_dap then
    java.dap.config_dap()
  end
end

local function start_config(config)
  local dap = require('dap')
  local vars = placeholder_vars()
  local expanded = expand_placeholders(normalize_config(config), vars)

  if expanded.type == 'java' then
    prepare_java_dap()
  end

  dap.run(expanded)
end

function M.edit_config(path_or_bufnr)
  local path = config_path(path_or_bufnr)
  json_meta.open(path, config_schema, {
    title = 'Project DAP Configurations',
    description = path,
  })
end

function M.start(path_or_bufnr)
  local path = config_path(path_or_bufnr)
  local config = decode_config(path)
  local configurations = config.configurations or {}

  if #configurations == 0 then
    vim.notify('No debug configurations found in ' .. path, vim.log.levels.WARN)
    return
  end

  if #configurations == 1 then
    start_config(configurations[1])
    return
  end

  vim.ui.select(configurations, {
    prompt = 'Select debug configuration',
    format_item = function(item)
      return string.format('%s (%s/%s)', item.name or '<unnamed>', item.type or '?', item.request or '?')
    end,
  }, function(choice)
    if not choice then
      return
    end
    start_config(choice)
  end)
end

function M.toggle_breakpoint()
  require('dap').toggle_breakpoint()
end

function M.setup()
  vim.api.nvim_create_user_command('DebugConfigEdit', function()
    M.edit_config(0)
  end, {
    desc = 'Create or edit the project-local DAP config list',
  })

  vim.api.nvim_create_user_command('DebugStart', function()
    M.start(0)
  end, {
    desc = 'Start a debug session from the project-local config list',
  })

  vim.api.nvim_create_user_command('DebugToggleBreakpoint', function()
    M.toggle_breakpoint()
  end, {
    desc = 'Toggle a DAP breakpoint on the current line',
  })
end

return M
