local M = {}

local progress_by_client = {}
local recent_completion_timeout_ms = 5000
local recent_status_timeout_ms = 5000
local setup_done = false
local lsp_start_wrapped = false

local function now_ms()
  return (vim.uv or vim.loop).now()
end

local function truthy(value)
  if type(value) == 'boolean' then
    return value
  end

  if type(value) == 'number' then
    return value ~= 0
  end

  if type(value) == 'string' then
    local normalized = value:lower()
    return normalized == '1' or normalized == 'true' or normalized == 'yes' or normalized == 'on'
  end

  return false
end

local function get_jdtls_client(bufnr)
  local clients = vim.lsp.get_clients({ bufnr = bufnr or 0, name = 'jdtls' })
  return clients[1]
end

local function refresh_lualine()
  local ok, lualine = pcall(require, 'lualine')
  if ok then
    lualine.refresh({ place = { 'statusline' } })
  end
end

local function get_state(client_id)
  local state = progress_by_client[client_id]
  if state then
    return state
  end

  state = {
    tokens = {},
    last_message = nil,
    last_message_at = 0,
    last_done_at = 0,
  }
  progress_by_client[client_id] = state
  return state
end

local function format_progress(value)
  local pieces = {}

  if value.percentage then
    table.insert(pieces, string.format('%d%%', value.percentage))
  end

  if value.title and value.title ~= '' then
    table.insert(pieces, value.title)
  end

  if value.message and value.message ~= '' and value.message ~= value.title then
    table.insert(pieces, value.message)
  end

  return table.concat(pieces, ' ')
end

local function latest_active_message(state)
  local latest
  for _, item in pairs(state.tokens) do
    if not latest or item.updated_at > latest.updated_at then
      latest = item
    end
  end
  return latest
end

function M.enable_spring_boot_tools()
  if vim.g.nvim_java_enable_spring_boot_tools ~= nil then
    return truthy(vim.g.nvim_java_enable_spring_boot_tools)
  end

  return true
end

function M.enable_spring_boot_network()
  if vim.g.nvim_java_enable_spring_boot_network ~= nil then
    return truthy(vim.g.nvim_java_enable_spring_boot_network)
  end

  return true
end

function M.download_sources()
  if vim.g.nvim_java_download_sources ~= nil then
    return truthy(vim.g.nvim_java_download_sources)
  end

  return false
end

function M.performance_mode_enabled()
  if vim.g.nvim_java_perf_mode ~= nil then
    return truthy(vim.g.nvim_java_perf_mode)
  end

  return true
end

function M.spring_boot_settings()
  if M.enable_spring_boot_network() then
    return {}
  end

  return {
    ['boot-java'] = {
      ['change-detection'] = {
        on = false,
      },
      ['live-information'] = {
        ['all-local-java-processes'] = false,
        ['automatic-connection'] = {
          on = false,
        },
        ['fetch-data'] = {
          ['max-retries'] = 1,
          ['retry-delay-in-seconds'] = 1,
        },
      },
      ['modulith-project-tracking'] = false,
      rewrite = {
        refactorings = {
          on = false,
        },
        ['scan-files'] = {},
      },
    },
  }
end

function M.performance_jvm_args()
  if not M.performance_mode_enabled() then
    return {}
  end

  return {
    '--jvm-arg=-Xms1G',
    '--jvm-arg=-Xmx2G',
    '--jvm-arg=-Xshare:auto',
    '--jvm-arg=-XX:+UseStringDeduplication',
    '--jvm-arg=-XX:ReservedCodeCacheSize=256m',
    '--jvm-arg=-Dsun.zip.disableMemoryMapping=false',
  }
end

local function extend_jdtls_cmd(cmd)
  if not vim.islist(cmd) then
    return cmd
  end

  local extended = vim.deepcopy(cmd)
  local existing = {}

  for _, item in ipairs(extended) do
    existing[item] = true
  end

  for _, item in ipairs(M.performance_jvm_args()) do
    if not existing[item] then
      table.insert(extended, item)
    end
  end

  return extended
end

local function restart_jdtls()
  local ok, lsp_utils = pcall(require, 'java-core.utils.lsp')
  if ok then
    lsp_utils.restart_ls('jdtls')
    return
  end

  vim.lsp.enable('jdtls', false)
  for _, client in ipairs(vim.lsp.get_clients({ name = 'jdtls' })) do
    client:stop(true)
  end
  vim.defer_fn(function()
    vim.lsp.enable('jdtls')
  end, 500)
end

local function set_performance_mode(enabled)
  vim.g.nvim_java_perf_mode = enabled
  if get_jdtls_client(0) then
    restart_jdtls()
  end
end

function M.nvim_java_config()
  return {
    lombok = {
      enable = true,
    },
    spring_boot_tools = {
      enable = M.enable_spring_boot_tools(),
    },
  }
end

function M.has_jdtls(bufnr)
  return get_jdtls_client(bufnr) ~= nil
end

function M.progress_status()
  local client = get_jdtls_client(0)
  if not client then
    return ''
  end

  local state = progress_by_client[client.id]
  if not state then
    return ''
  end

  local active = latest_active_message(state)
  if active and active.text ~= '' then
    return 'jdtls ' .. active.text
  end

  local now = now_ms()
  if state.last_message and now - state.last_message_at <= recent_status_timeout_ms then
    return 'jdtls ' .. state.last_message
  end

  if state.last_done_at > 0 and now - state.last_done_at <= recent_completion_timeout_ms then
    return 'jdtls ready'
  end

  return ''
end

function M.show_status()
  local status = M.progress_status()
  if status == '' then
    status = M.has_jdtls(0) and 'jdtls idle' or 'jdtls not attached'
  end

  vim.notify(status, vim.log.levels.INFO)
end

function M.show_performance_mode()
  local enabled = M.performance_mode_enabled()
  vim.notify('JDTLS performance mode: ' .. (enabled and 'on' or 'off'), vim.log.levels.INFO)
end

function M.toggle_performance_mode()
  set_performance_mode(not M.performance_mode_enabled())
  M.show_performance_mode()
end

function M.set_performance_mode(mode)
  if mode == 'on' then
    set_performance_mode(true)
  elseif mode == 'off' then
    set_performance_mode(false)
  elseif mode == 'toggle' then
    set_performance_mode(not M.performance_mode_enabled())
  end

  M.show_performance_mode()
end

function M.setup()
  if setup_done then
    return
  end
  setup_done = true

  local group = vim.api.nvim_create_augroup('UserJavaStatus', { clear = true })

  if not lsp_start_wrapped then
    local original_lsp_start = vim.lsp.start
    vim.lsp.start = function(config, opts)
      local patched = config

      if type(config) == 'table' and config.name then
        patched = vim.deepcopy(config)

        if config.name == 'jdtls' then
          patched.cmd = extend_jdtls_cmd(patched.cmd)
        end

        if config.name == 'jdtls' or config.name == 'spring-boot' then
          patched.settings = vim.tbl_deep_extend('force', patched.settings or {}, M.spring_boot_settings())
        end
      end

      return original_lsp_start(patched, opts)
    end

    lsp_start_wrapped = true
  end

  pcall(vim.api.nvim_create_autocmd, 'LspProgress', {
    group = group,
    callback = function(event)
      local client = vim.lsp.get_client_by_id(event.data.client_id)
      if not client or client.name ~= 'jdtls' then
        return
      end

      local value = event.data.params.value
      local token = tostring(event.data.params.token)
      local state = get_state(client.id)

      if value.kind == 'end' then
        state.tokens[token] = nil
        state.last_done_at = now_ms()
      else
        state.tokens[token] = {
          text = format_progress(value),
          updated_at = now_ms(),
        }
      end

      refresh_lualine()
    end,
  })

  local previous_language_status = vim.lsp.handlers['language/status']
  vim.lsp.handlers['language/status'] = function(err, result, ctx, config)
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    if client and client.name == 'jdtls' then
      local message = type(result) == 'table' and (result.message or result.type) or tostring(result)
      if message and message ~= '' then
        local state = get_state(client.id)
        state.last_message = message
        state.last_message_at = now_ms()
        refresh_lualine()
      end
    end

    if previous_language_status then
      return previous_language_status(err, result, ctx, config)
    end
  end

  vim.api.nvim_create_autocmd('LspDetach', {
    group = group,
    callback = function(event)
      progress_by_client[event.data.client_id] = nil
      refresh_lualine()
    end,
  })

  vim.api.nvim_create_user_command('JdtlsStatus', function()
    M.show_status()
  end, { desc = 'Show current JDTLS status' })

  vim.api.nvim_create_user_command('JdtlsPerformanceMode', function(opts)
    local arg = opts.args ~= '' and opts.args or 'status'
    if arg == 'status' then
      M.show_performance_mode()
      return
    end

    if arg ~= 'on' and arg ~= 'off' and arg ~= 'toggle' then
      vim.notify('Usage: :JdtlsPerformanceMode [on|off|toggle|status]', vim.log.levels.ERROR)
      return
    end

    M.set_performance_mode(arg)
  end, {
    desc = 'Toggle JDTLS performance mode',
    nargs = '?',
    complete = function()
      return { 'on', 'off', 'toggle', 'status' }
    end,
  })
end

return M
