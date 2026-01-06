-- [[ user.util ]]
-- Utility functions

local M = {}

--- Toggles between C/C++ header and source files.
function M.toggle_header_source()
  local current_file = vim.fn.expand('%:p')
  local base_name = vim.fn.expand('%:r')
  local ext = vim.fn.expand('%:e')

  local target_file = ''

  local header_exts = { 'h', 'hpp', 'hxx' }
  local source_exts = { 'c', 'cpp', 'cxx', 'cc' }

  local function file_exists(name)
    return vim.fn.filereadable(name) == 1
  end

  if vim.tbl_contains(header_exts, ext) then
    -- Current is a header, find a source
    for _, s_ext in ipairs(source_exts) do
      local potential_target = base_name .. '.' .. s_ext
      if file_exists(potential_target) then
        target_file = potential_target
        break
      end
    end
  elseif vim.tbl_contains(source_exts, ext) then
    -- Current is a source, find a header
    for _, h_ext in ipairs(header_exts) do
      local potential_target = base_name .. '.' .. h_ext
      if file_exists(potential_target) then
        target_file = potential_target
        break
      end
    end
  else
    vim.notify('Not a C/C++ header or source file.', vim.log.levels.WARN)
    return
  end

  if target_file ~= '' then
    vim.cmd.edit(target_file)
  else
    vim.notify('Could not find corresponding file for: ' .. vim.fn.expand('%'), vim.log.levels.WARN)
  end
end

-- Autoformat on save, unless filename contains "wasm"
vim.api.nvim_create_autocmd("BufWritePre", {
  group = vim.api.nvim_create_augroup("AutoFormat", { clear = true }),
  callback = function()
    local filename = vim.fn.expand("%:t")
    if string.find(filename, "wasm", 1, true) then
      return
    end

    -- Handle Go imports via LSP
    if vim.bo.filetype == "go" then
      local params = vim.lsp.util.make_range_params()
      params.context = { only = { "source.organizeImports" } }
      local result = vim.lsp.buf_request_sync(0, "textDocument/codeAction", params, 1000)
      for cid, res in pairs(result or {}) do
        for _, r in pairs(res.result or {}) do
          if r.edit then
            vim.lsp.util.apply_workspace_edit(r.edit, "utf-16")
          else
            vim.lsp.buf.execute_command(r.command)
          end
        end
      end
    end

    if not string.find(filename, "wasm", 1, true) then -- 1 for start position, true for plain search
      vim.lsp.buf.format({ async = false })
    end
  end,
})

--- Expands the macro under the cursor using LSP code actions.
function M.expand_macro()
  vim.lsp.buf.code_action({
    filter = function(action)
      return action.title:lower():find("expand macro") ~= nil
    end,
    apply = true,
  })
end

return M
