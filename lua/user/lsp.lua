local M = {}

-- Configure diagnostics globally
vim.diagnostic.config({
  severity_sort = true, -- Show highest severity diagnostic (Error over Warning) on the same line
})

-- Silently handle and ignore LSP signature help RPC errors (such as Java's ClassCastException)
local original_sig_help_handler = vim.lsp.handlers["textDocument/signatureHelp"]
vim.lsp.handlers["textDocument/signatureHelp"] = function(err, result, ctx, config)
  if err then
    -- Suppress all signatureHelp errors to avoid annoying popups/messages
    return
  end
  if original_sig_help_handler then
    original_sig_help_handler(err, result, ctx, config)
  else
    vim.lsp.with(vim.lsp.handlers.signature_help, {
      border = 'rounded',
    })(err, result, ctx, config)
  end
end

local function buf_map(bufnr, mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, {
    buffer = bufnr,
    silent = true,
    desc = desc,
  })
end

local function organize_imports()
  vim.lsp.buf.code_action({
    apply = true,
    context = {
      only = { 'source.organizeImports' },
      diagnostics = {},
    },
  })
end

local function supports_document_formatting(client)
  return client.server_capabilities
    and client.server_capabilities.documentFormattingProvider
end

local function supports_range_formatting(client)
  if client.supports_method and client:supports_method('textDocument/rangeFormatting') then
    return true
  end

  return client.server_capabilities
    and client.server_capabilities.documentRangeFormattingProvider
end

local function get_visual_range(bufnr)
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_row = start_pos[2] - 1
  local start_col = math.max(start_pos[3] - 1, 0)
  local end_row = end_pos[2] - 1
  local end_col = math.max(end_pos[3], 0)

  if start_row < 0 or end_row < 0 then
    return nil
  end

  if start_row > end_row or (start_row == end_row and start_col > end_col) then
    start_row, end_row = end_row, start_row
    start_col, end_col = end_col, start_col
  end

  local visual_mode = vim.fn.visualmode()
  if visual_mode == 'V' then
    start_col = 0
    end_col = #vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1]
  end

  return {
    start = { start_row, start_col },
    ['end'] = { end_row, end_col },
  }
end

local function jump_to_current_class_definition()
  local ok, ts_utils = pcall(require, 'nvim-treesitter.ts_utils')
  local parser = nil
  if ok then
    local success, p = pcall(vim.treesitter.get_parser, 0)
    if success then
      parser = p
    end
  end

  local target_types = {
    class_declaration = true,
    class_definition = true,
    interface_declaration = true,
    enum_declaration = true,
    record_declaration = true,
    struct_specifier = true,
    struct_declaration = true,
    trait_declaration = true,
    type_declaration = true,
  }

  local found_node = nil
  if parser then
    local tree = parser:parse()[1]
    if tree then
      local root = tree:root()
      local function traverse(node)
        if found_node then return end
        local type = node:type()
        if target_types[type] then
          for child in node:iter_children() do
            if child:type() == 'identifier' or child:type() == 'type_identifier' then
              found_node = child
              return
            end
          end
          found_node = node
          return
        end
        for child in node:iter_children() do
          traverse(child)
          if found_node then return end
        end
      end
      traverse(root)
    end
  end

  if found_node then
    local start_row, start_col, _, _ = found_node:range()
    vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
  else
    -- Fallback to regex search
    local line_count = vim.api.nvim_buf_line_count(0)
    for i = 1, line_count do
      local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
      if line:match("%f[%w]class%s+[%w_]+") or
         line:match("%f[%w]interface%s+[%w_]+") or
         line:match("%f[%w]enum%s+[%w_]+") or
         line:match("%f[%w]record%s+[%w_]+") or
         line:match("%f[%w]struct%s+[%w_]+") or
         line:match("%f[%w]trait%s+[%w_]+") or
         line:match("%f[%w]type%s+[%w_]+") then
        vim.api.nvim_win_set_cursor(0, { i, 0 })
        return
      end
    end
    vim.notify("Could not find class definition", vim.log.levels.WARN)
  end
end

local function jump_to_class()
  vim.ui.input({ prompt = 'Class: ' }, function(input)
    local query = vim.trim(input or '')
    if query == '' then
      return
    end

    local responses = vim.lsp.buf_request_sync(0, 'workspace/symbol', {
      query = query,
    }, 2000)
    local matches = {}
    local wanted = query:lower()
    local class_kinds = {
      [vim.lsp.protocol.SymbolKind.Class] = true,
      [vim.lsp.protocol.SymbolKind.Interface] = true,
      [vim.lsp.protocol.SymbolKind.Enum] = true,
      [vim.lsp.protocol.SymbolKind.Struct] = true,
    }

    for _, response in pairs(responses or {}) do
      for _, item in ipairs(response.result or {}) do
        local name = item.name or ''
        local simple_name = name:match('([%w_$]+)$') or name
        local lowered_name = name:lower()
        local lowered_simple = simple_name:lower()
        if class_kinds[item.kind] and (
          lowered_simple == wanted
          or lowered_name == wanted
          or lowered_simple:find(wanted, 1, true) == 1
          or lowered_name:find(wanted, 1, true) ~= nil
        ) then
          table.insert(matches, item)
        end
      end
    end

    table.sort(matches, function(left, right)
      return (left.name or '') < (right.name or '')
    end)

    if #matches == 0 then
      vim.notify('No matching class found for: ' .. query, vim.log.levels.INFO)
      return
    end

    local encoding = 'utf-16'
    local clients = vim.lsp.get_clients({ bufnr = 0 })
    if clients[1] and clients[1].offset_encoding then
      encoding = clients[1].offset_encoding
    end

    local function jump(item)
      local location = item.location
      if location and location.uri and location.range then
        vim.lsp.util.jump_to_location(location, encoding, true)
        return
      end
      if location and location.targetUri and location.targetRange then
        vim.lsp.util.jump_to_location({
          uri = location.targetUri,
          range = location.targetRange,
        }, encoding, true)
      end
    end

    if #matches == 1 then
      jump(matches[1])
      return
    end

    vim.ui.select(matches, {
      prompt = 'Jump to class',
      format_item = function(item)
        local container = item.containerName and item.containerName ~= '' and (' — ' .. item.containerName) or ''
        return (item.name or '<unknown>') .. container
      end,
    }, function(choice)
      if choice then
        jump(choice)
      end
    end)
  end)
end

local function format_visual_selection()
  local range = get_visual_range(0)
  if not range then
    vim.notify('No visual selection available for formatting.', vim.log.levels.WARN)
    return
  end

  vim.lsp.buf.format({
    async = true,
    range = range,
  })
end

local function attach_java_keymaps(bufnr)
  buf_map(bufnr, 'n', '<leader>jo', organize_imports, 'Java: Organize imports')
  buf_map(bufnr, { 'n', 'v' }, '<leader>jv', '<cmd>JavaRefactorExtractVariable<CR>', 'Java: Extract variable')
  buf_map(bufnr, { 'n', 'v' }, '<leader>jV', '<cmd>JavaRefactorExtractVariableAllOccurrence<CR>', 'Java: Extract variable (all)')
  buf_map(bufnr, { 'n', 'v' }, '<leader>jc', '<cmd>JavaRefactorExtractConstant<CR>', 'Java: Extract constant')
  buf_map(bufnr, { 'n', 'v' }, '<leader>jm', '<cmd>JavaRefactorExtractMethod<CR>', 'Java: Extract method')
  buf_map(bufnr, { 'n', 'v' }, '<leader>jf', '<cmd>JavaRefactorExtractField<CR>', 'Java: Extract field')
  buf_map(bufnr, 'n', '<leader>jr', '<cmd>JavaRunnerRunMain<CR>', 'Java: Run main')
  buf_map(bufnr, 'n', '<leader>js', '<cmd>JavaRunnerStopMain<CR>', 'Java: Stop main')
  buf_map(bufnr, 'n', '<leader>jl', '<cmd>JavaRunnerToggleLogs<CR>', 'Java: Toggle runner logs')
  buf_map(bufnr, 'n', '<leader>jtc', '<cmd>JavaTestRunCurrentClass<CR>', 'Java: Run test class')
  buf_map(bufnr, 'n', '<leader>jtm', '<cmd>JavaTestRunCurrentMethod<CR>', 'Java: Run test method')
  buf_map(bufnr, 'n', '<leader>jtr', '<cmd>JavaTestViewLastReport<CR>', 'Java: View last test report')
  buf_map(bufnr, 'n', '<leader>jj', '<cmd>JavaSettingsChangeRuntime<CR>', 'Java: Change runtime')
  buf_map(bufnr, 'n', '<leader>ji', M.override_methods, 'Java: Override/Implement methods')
end

function M.jdtls_settings()
  return {
    java = {
      eclipse = {
        downloadSources = true,
      },
      maven = {
        downloadSources = true,
      },
      contentProvider = {
        preferred = 'fernflower',
      },
      configuration = {
        updateBuildConfiguration = 'automatic',
      },
      implementationsCodeLens = {
        enabled = true,
      },
      referencesCodeLens = {
        enabled = true,
      },
      signatureHelp = {
        enabled = true,
      },
      debug = {
        settings = {
          stepping = {
            skipClasses = {
              '$JDK',
              '$Libraries',
              'org.springframework.*',
              'sun.*',
              'jdk.*',
              'com.sun.*',
            },
            skipConstructors = false,
            skipStaticInitializers = true,
            skipSynthetics = true,
          },
          stepFilters = {
            skipClasses = {
              '$JDK',
              '$Libraries',
              'org.springframework.*',
              'sun.*',
              'jdk.*',
              'com.sun.*',
            },
            skipConstructors = false,
            skipStaticInitializers = true,
            skipSynthetics = true,
          },
        },
      },
    },
  }
end

function M.override_methods()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = 'jdtls' })[1]
  local position_encoding = client and client.offset_encoding or 'utf-16'
  local params = vim.lsp.util.make_range_params(0, position_encoding)
  params.context = {
    diagnostics = vim.diagnostic.get(bufnr, { lnum = cursor[1] - 1 }),
  }
  vim.lsp.buf_request(0, 'textDocument/codeAction', params, function(err, result, ctx, config)
    if err then
      vim.notify('Failed to fetch override actions: ' .. err.message, vim.log.levels.WARN)
      return
    end

    if not result then
      return
    end

    for _, action in ipairs(result) do
      local title = action.title or ""
      if title:match("Override/Implement Methods") or title:match("override/implement") then
        local action_client = vim.lsp.get_client_by_id(ctx.client_id)
        if action_client then
          local cmd = action.command or action
          if type(cmd) == "table" and cmd.command then
            local cmd_name = cmd.command
            local local_fn = action_client.commands and action_client.commands[cmd_name]
            if not local_fn and vim.lsp.commands then
              local_fn = vim.lsp.commands[cmd_name]
            end

            if local_fn then
              local command_params = params
              if type(cmd.arguments) == 'table' and type(cmd.arguments[1]) == 'table' then
                command_params = cmd.arguments[1]
              end
              local_fn(cmd.arguments, {
                client_id = ctx.client_id,
                bufnr = ctx.bufnr or bufnr,
                method = ctx.method,
                params = command_params,
                version = ctx.version,
              })
            elseif action_client.exec_cmd then
              action_client:exec_cmd(cmd, { bufnr = ctx.bufnr or bufnr })
            else
              action_client.request('workspace/executeCommand', cmd, function(exec_err, exec_res)
                if exec_err then
                  vim.notify("Error executing override: " .. exec_err.message, vim.log.levels.WARN)
                end
              end, 0)
            end
          else
            if action.edit then
              vim.lsp.util.apply_workspace_edit(action.edit, action_client.offset_encoding or position_encoding)
            end
          end
        end
        return
      end
    end
    vim.notify("Override/Implement Methods code action not found at cursor position", vim.log.levels.WARN)
  end)
end

function M.on_attach(client, bufnr)
  local builtin = require('telescope.builtin')
  local ok_user_java, user_java = pcall(require, 'user.java')

  buf_map(bufnr, 'n', '<C-]>', vim.lsp.buf.definition, 'Go to Definition')
  buf_map(bufnr, 'n', 'gd', vim.lsp.buf.definition, 'Go to Definition')
  buf_map(bufnr, 'n', 'gr', function()
    require('telescope.builtin').lsp_references({
      include_declaration = true,
      show_line = true,
    })
  end, 'Go to References (with preview)')
  buf_map(bufnr, 'n', 'gD', vim.lsp.buf.declaration, 'Go to Declaration')
  buf_map(bufnr, 'n', 'K', vim.lsp.buf.hover, 'Hover')
  buf_map(bufnr, 'n', 'ff', vim.lsp.buf.code_action, 'Code Action')
  buf_map(bufnr, 'n', '<leader>rn', vim.lsp.buf.rename, 'Rename')

  buf_map(bufnr, 'n', '<leader>ld', vim.lsp.buf.definition, 'LSP: Go to definition')
  buf_map(bufnr, 'n', '<leader>lD', vim.lsp.buf.declaration, 'LSP: Go to declaration')
  buf_map(bufnr, 'n', '<leader>lr', function()
    require('telescope.builtin').lsp_references({
      include_declaration = true,
      show_line = false,
      previewer = (function()
        local p = require('telescope.config').values.qflist_previewer({
          include_declaration = true,
          show_line = false,
        })
        local original_preview = p.preview
        p.preview = function(self, entry, status)
          original_preview(self, entry, status)
          if entry and entry.lnum and entry.col then
            local p_bufnr = self.state.bufnr
            if p_bufnr and vim.api.nvim_buf_is_valid(p_bufnr) then
              vim.schedule(function()
                if not vim.api.nvim_buf_is_valid(p_bufnr) then return end
                local lines = vim.api.nvim_buf_get_lines(p_bufnr, entry.lnum - 1, entry.lnum, false)
                local line = lines[1]
                if line then
                  local col = entry.col
                  local sub = line:sub(col)
                  local word = sub:match("^[%w_]+")
                  local word_len = word and #word or 1
                  local ns = vim.api.nvim_create_namespace("telescope_lsp_ref_highlight")
                  vim.api.nvim_buf_clear_namespace(p_bufnr, ns, 0, -1)
                  vim.api.nvim_buf_add_highlight(p_bufnr, ns, "TelescopePreviewMatch", entry.lnum - 1, col - 1, col - 1 + word_len)
                end
              end)
            end
          end
        end
        return p
      end)(),
    })
  end, 'LSP: Go to references (with preview)')
  buf_map(bufnr, 'n', '<leader>li', vim.lsp.buf.implementation, 'LSP: Go to implementation')
  buf_map(bufnr, 'n', '<leader>lc', jump_to_class, 'LSP: Jump to class')
  buf_map(bufnr, 'n', '<leader>lC', jump_to_current_class_definition, 'LSP: Jump to current class definition')
  buf_map(bufnr, 'n', '<leader>lt', vim.lsp.buf.type_definition, 'LSP: Go to type definition')
  buf_map(bufnr, 'n', '<leader>lh', vim.lsp.buf.hover, 'LSP: Hover')
  buf_map(bufnr, 'n', '<leader>la', vim.lsp.buf.code_action, 'LSP: Code action')
  buf_map(bufnr, 'n', '<leader>lR', vim.lsp.buf.rename, 'LSP: Rename')
  buf_map(bufnr, 'n', '<leader>ls', builtin.lsp_document_symbols, 'LSP: Document symbols')
  buf_map(bufnr, 'n', '<leader>lS', builtin.lsp_dynamic_workspace_symbols, 'LSP: Workspace symbols')
  buf_map(bufnr, 'n', '<leader>le', vim.diagnostic.open_float, 'LSP: Line diagnostics')
  buf_map(bufnr, 'n', '<leader>ln', vim.diagnostic.goto_next, 'LSP: Next diagnostic')
  buf_map(bufnr, 'n', '<leader>lp', vim.diagnostic.goto_prev, 'LSP: Previous diagnostic')

  if supports_document_formatting(client) then
    buf_map(bufnr, 'n', '<leader>lf', function()
      vim.lsp.buf.format({ async = true })
    end, 'LSP: Format buffer')
  end

  if supports_range_formatting(client) then
    buf_map(bufnr, 'x', '<leader>lf', format_visual_selection, 'LSP: Format selection')
  end

  if client.name == 'jdtls' then
    attach_java_keymaps(bufnr)
  end

  if ok_user_java then
    user_java.attach_mapper_keymaps(bufnr)
  end
end

return M
