local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

-- Load required plugins
require('lazy').load({ plugins = { 'nvim-cmp', 'nvim-dap', 'nvim-jdtls' } })

local cmp = require('cmp')
local dap = require('dap')

-- 1. Test DAP Completion Source
local mock_session = {
  seq = 1,
  threads = {},
  stopped_thread_id = 1,
  current_frame = { id = 42 },
  capabilities = { supportsCompletionsRequest = true },
  request = function(self, command, args, cb)
    if command == "completions" then
      support.expect_equal('dap completions frameId', args.frameId, 42)
      support.expect_equal('dap completions text', args.text, "user.")
      cb(nil, {
        targets = {
          { label = "getName()", text = "getName()", type = "method" },
          { label = "id", text = "id", type = "field" },
          { label = "getEmail()", text = "getEmail()", type = "method" },
        }
      })
    else
      cb(nil, {})
    end
  end
}

dap.session = function()
  return mock_session
end

-- Initialize DAP module
local user_dap = require('user.dap')
user_dap.setup()

-- Create a dap-repl buffer and trigger FileType autocmd
local repl_buf = vim.api.nvim_create_buf(false, true)
vim.bo[repl_buf].buftype = 'prompt'
vim.bo[repl_buf].filetype = 'dap-repl'
vim.api.nvim_set_current_buf(repl_buf)

-- Retrieve the registered dap source from cmp
local dap_source = nil
if cmp.core and cmp.core.sources then
  for _, s in ipairs(cmp.core.sources) do
    if s.name == 'dap' then
      dap_source = s.source
      break
    end
  end
end

support.expect_true('dap cmp source registered', dap_source ~= nil)

-- Check trigger characters
local triggers = dap_source:get_trigger_characters()
support.expect_true('trigger characters includes dot', vim.tbl_contains(triggers, '.'))

-- Test dap_source completion output
local completed_items = nil
dap_source:complete({
  context = {
    cursor = { col = 5, line = 0, row = 1 },
    cursor_line = "user.",
  }
}, function(result)
  completed_items = result.items
end)

support.expect_true('completion callback returned items', completed_items ~= nil and #completed_items == 3)
support.expect_equal('first completion item label', completed_items[1].label, 'getName()')
support.expect_equal('first completion item kind is Method', completed_items[1].kind, cmp.lsp.CompletionItemKind.Method)
support.expect_equal('second completion item label', completed_items[2].label, 'id')
support.expect_equal('second completion item kind is Field', completed_items[2].kind, cmp.lsp.CompletionItemKind.Field)

mock_session.request = function(self, command, args, cb)
  if command == "completions" then
    cb(nil, {
      targets = {
        { label = "field", text = "field", type = "field", start = 6 },
      }
    })
  else
    cb(nil, {})
  end
end

local replacement_items = nil
dap_source:complete({
  context = {
    cursor = { col = 7, line = 1, row = 2 },
    cursor_line = "> user.",
  }
}, function(result)
  replacement_items = result.items
end)

support.expect_true('dap completion start-only target returned item', replacement_items ~= nil and #replacement_items == 1)
support.expect_true('dap completion start-only target adds textEdit', replacement_items[1].textEdit ~= nil)
support.expect_equal('dap completion textEdit start line', replacement_items[1].textEdit.range.start.line, 1)
support.expect_equal('dap completion textEdit start character', replacement_items[1].textEdit.range.start.character, 7)
support.expect_equal('dap completion textEdit end character defaults to zero-length', replacement_items[1].textEdit.range["end"].character, 7)
support.expect_equal('dap completion textEdit new text', replacement_items[1].textEdit.newText, 'field')

-- 2. Test Extract Method on 1st Attempt (Visual Mode Marks)
support.reset({
  'public class Demo {',
  '    public void test() {',
  '        int a = 1;',
  '        int b = 2;',
  '        int sum = a + b;',
  '    }',
  '}'
}, 'java', 'java')

local jdtls = require('jdtls')
local extract_params_received = nil

-- Mock jdtls request or apply refactoring
local original_make_params = vim.lsp.util.make_given_range_params
vim.fn.setpos("'<", { 0, 3, 1, 0 })
vim.fn.setpos("'>", { 0, 5, 24, 0 })

-- Set cursor to line 3 and enter visual mode
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.cmd('normal! V2j')

-- Trigger <ESC><cmd>lua require("jdtls").extract_method(true)<CR>
local term_cmd = vim.api.nvim_replace_termcodes('<ESC><cmd>lua require("jdtls").extract_method(true)<CR>', true, false, true)
vim.api.nvim_feedkeys(term_cmd, 'xt', false)

-- Check '< and '> marks after visual exit
local mark_start = vim.fn.getpos("'<")
local mark_end = vim.fn.getpos("'>")

support.expect_equal('start mark line on 1st attempt', mark_start[2], 3)
support.expect_equal('end mark line on 1st attempt', mark_end[2], 5)

support.flush()
