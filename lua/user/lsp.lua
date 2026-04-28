local M = {}

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
        updateBuildConfiguration = 'interactive',
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
    },
  }
end

function M.on_attach(client, bufnr)
  local builtin = require('telescope.builtin')

  buf_map(bufnr, 'n', '<C-]>', vim.lsp.buf.definition, 'Go to Definition')
  buf_map(bufnr, 'n', 'gd', vim.lsp.buf.definition, 'Go to Definition')
  buf_map(bufnr, 'n', 'gr', vim.lsp.buf.references, 'Go to References')
  buf_map(bufnr, 'n', 'gD', vim.lsp.buf.declaration, 'Go to Declaration')
  buf_map(bufnr, 'n', 'K', vim.lsp.buf.hover, 'Hover')
  buf_map(bufnr, 'n', 'ff', vim.lsp.buf.code_action, 'Code Action')
  buf_map(bufnr, 'n', '<leader>rn', vim.lsp.buf.rename, 'Rename')

  buf_map(bufnr, 'n', '<leader>ld', vim.lsp.buf.definition, 'LSP: Go to definition')
  buf_map(bufnr, 'n', '<leader>lD', vim.lsp.buf.declaration, 'LSP: Go to declaration')
  buf_map(bufnr, 'n', '<leader>lr', vim.lsp.buf.references, 'LSP: Go to references')
  buf_map(bufnr, 'n', '<leader>li', vim.lsp.buf.implementation, 'LSP: Go to implementation')
  buf_map(bufnr, 'n', '<leader>lt', vim.lsp.buf.type_definition, 'LSP: Go to type definition')
  buf_map(bufnr, 'n', '<leader>lh', vim.lsp.buf.hover, 'LSP: Hover')
  buf_map(bufnr, 'n', '<leader>la', vim.lsp.buf.code_action, 'LSP: Code action')
  buf_map(bufnr, 'n', '<leader>lR', vim.lsp.buf.rename, 'LSP: Rename')
  buf_map(bufnr, 'n', '<leader>ls', builtin.lsp_document_symbols, 'LSP: Document symbols')
  buf_map(bufnr, 'n', '<leader>lS', builtin.lsp_dynamic_workspace_symbols, 'LSP: Workspace symbols')
  buf_map(bufnr, 'n', '<leader>le', vim.diagnostic.open_float, 'LSP: Line diagnostics')
  buf_map(bufnr, 'n', '<leader>ln', vim.diagnostic.goto_next, 'LSP: Next diagnostic')
  buf_map(bufnr, 'n', '<leader>lp', vim.diagnostic.goto_prev, 'LSP: Previous diagnostic')

  if client.server_capabilities.documentFormattingProvider then
    buf_map(bufnr, 'n', '<leader>lf', function()
      vim.lsp.buf.format({ async = true })
    end, 'LSP: Format buffer')
  end

  if client.name == 'jdtls' then
    attach_java_keymaps(bufnr)
  end
end

return M
