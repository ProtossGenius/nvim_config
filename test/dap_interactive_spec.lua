local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

-- Wait for lazy.nvim to finish loading plugins (e.g. nvim-cmp, nvim-dap-ui)
require('lazy').load({ plugins = { 'nvim-cmp', 'nvim-dap', 'nvim-dap-ui', 'nvim-nio' } })

local cmp = require('cmp')
local dap = require('dap')
local user_dap = require('user.dap')
local mock_session

local function current_source_names()
  local names = {}
  for _, source in ipairs(cmp.get_config().sources or {}) do
    table.insert(names, source.name)
  end
  return names
end

local function cmp_enabled()
  local enabled = cmp.get_config().enabled
  if type(enabled) == 'function' then
    return enabled()
  end
  return enabled
end

local function get_dap_cmp_source()
  for _, source in pairs(cmp.core.sources) do
    if source.name == 'dap' then
      return source
    end
  end
end

local function run_dap_source_completion(bufnr, line, reason, reset_source)
  local done = false
  local state = {}
  local previous_virtualedit = vim.o.virtualedit

  vim.o.virtualedit = 'all'
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line })
  vim.api.nvim_win_set_cursor(0, { 1, #line })

  local source = get_dap_cmp_source()
  if reset_source then
    source:reset()
  end
  mock_session.last_completion_args = nil
  local ctx = cmp.core:get_context({ reason = reason or cmp.ContextReason.Manual })

  source:complete(ctx, function()
    local entry = source.entries[1]
    state.request = mock_session.last_completion_args
    state.request_offset = source.request_offset
    state.entry_count = #source.entries
    state.entry_offset = entry and entry.offset or nil
    state.insert_start = entry and entry.insert_range and entry.insert_range.start.character or nil
    state.insert_end = entry and entry.insert_range and entry.insert_range["end"].character or nil
    state.label = entry and entry.completion_item.label or nil
    done = true
  end)

  vim.wait(1000, function()
    return done
  end, 20)

  vim.o.virtualedit = previous_virtualedit
  return state
end

-- 1. Mock DAP session first before anything else loads dapui client
local mock_source_path = vim.fn.stdpath('config') .. "/init.lua"
mock_session = {
  seq = 1,
  threads = {
    [1] = {
      id = 1,
      name = "main",
      frames = {
        {
          id = 1,
          name = "test_frame",
          line = 10,
          column = 1,
          source = {
            name = "init.lua",
            path = mock_source_path
          }
        }
      }
    }
  },
  stopped_thread_id = 1,
  current_frame = { id = 1 },
  capabilities = { supportsCompletionsRequest = true },
  _frame_set = function(self, frame)
    self.current_frame = frame
  end,
  last_completion_args = nil,
  request = function(self, command, args, cb)
    if command == "stackTrace" then
      cb(nil, { stackFrames = {
        {
          id = 1,
          name = "test_frame",
          line = 10,
          column = 1,
          source = {
            name = "init.lua",
            path = mock_source_path
          }
        }
      }})
    elseif command == "completions" then
      self.last_completion_args = vim.deepcopy(args)
      local targets
      if args.text == 'user.ge' then
        targets = {
          {
            label = "getEmail() : String",
            text = "getEmail()",
            type = "function",
            start = 0,
          },
          {
            label = "getId() : Long",
            text = "getId()",
            type = "function",
            start = 0,
          },
        }
      elseif args.text == 'foo + ge' then
        targets = {
          {
            label = "getResult() : String",
            text = "getResult()",
            type = "function",
            start = 0,
          },
          {
            label = "getRetryCount() : int",
            text = "getRetryCount()",
            type = "function",
            start = 0,
          },
        }
      elseif args.text == 'this$' then
        targets = {
          {
            label = "this$0 : UserServiceImpl",
            text = "this$0",
            type = "property",
            start = 0,
          },
          {
            label = "this$1 : UserController",
            text = "this$1",
            type = "property",
            start = 0,
          },
        }
      elseif args.text == '用户.ge' then
        targets = {
          {
            label = "getDisplayName() : String",
            text = "getDisplayName()",
            type = "function",
            start = 0,
          },
          {
            label = "getId() : Long",
            text = "getId()",
            type = "function",
            start = 0,
          },
        }
      elseif args.text == '用户.显' then
        targets = {
          {
            label = "显示名() : String",
            text = "显示名()",
            type = "function",
            start = 0,
          },
          {
            label = "显示邮箱() : String",
            text = "显示邮箱()",
            type = "function",
            start = 0,
          },
        }
      else
        targets = {
          {
            label = "getName() : String",
            text = "getName()",
            type = "function",
            start = 0,
          },
          {
            label = "getId() : Long",
            text = "getId()",
            type = "function",
            start = 0,
          },
        }
      end
      cb(nil, { targets = targets })
    else
      cb(nil, {})
    end
  end
}

dap.session = function()
  return mock_session
end

-- 2. Load and setup dapui with the custom keymaps
local dapui = require('dapui')
dapui.setup({
  element_mappings = {
    stacks = {
      open = { "<CR>", "o" },
      expand = { "<Shift-CR>", "<2-LeftMouse>" }
    },
    breakpoints = {
      open = { "<CR>", "o" },
      expand = { "<Shift-CR>", "<2-LeftMouse>" }
    }
  }
})

-- 3. Verify cmp enabled status in prompt buffers
local dummy_buf = vim.api.nvim_create_buf(false, true)
vim.bo[dummy_buf].buftype = 'prompt'
vim.bo[dummy_buf].bufhidden = 'hide'
vim.bo[dummy_buf].filetype = 'dap-repl'
vim.api.nvim_set_current_buf(dummy_buf)
support.expect_true('cmp enabled in dap-repl', cmp_enabled())

local watches_buf = vim.api.nvim_create_buf(false, true)
vim.bo[watches_buf].buftype = 'prompt'
vim.bo[watches_buf].bufhidden = 'hide'
vim.bo[watches_buf].filetype = 'dapui_watches'
vim.api.nvim_set_current_buf(watches_buf)
support.expect_true('cmp enabled in dapui_watches', cmp_enabled())

local eval_buf = vim.api.nvim_create_buf(false, true)
vim.bo[eval_buf].buftype = 'prompt'
vim.bo[eval_buf].bufhidden = 'hide'
vim.bo[eval_buf].filetype = 'dapui_eval'
vim.api.nvim_set_current_buf(eval_buf)
support.expect_true('cmp enabled in dapui_eval', cmp_enabled())
support.expect_true('dapui_eval includes dap source', vim.tbl_contains(current_source_names(), 'dap'))
user_dap.setup_completion(eval_buf, {
  { name = 'buffer' },
})

local hover_buf = vim.api.nvim_create_buf(false, true)
vim.bo[hover_buf].buftype = 'prompt'
vim.bo[hover_buf].bufhidden = 'hide'
vim.bo[hover_buf].filetype = 'dapui_hover'
vim.api.nvim_set_current_buf(hover_buf)
support.expect_true('cmp enabled in dapui_hover', cmp_enabled())
support.expect_true('dapui_hover includes dap source', vim.tbl_contains(current_source_names(), 'dap'))

local eval_completion = run_dap_source_completion(eval_buf, '> user.')
support.expect_equal('dapui eval completion request text', eval_completion.request.text, 'user.')
support.expect_equal('dapui eval completion request column', eval_completion.request.column, 6)
support.expect_equal('dapui eval completion returns fresh entries', eval_completion.entry_count, 2)
support.expect_equal('dapui eval completion keeps request offset at cursor', eval_completion.request_offset, 8)
support.expect_equal('dapui eval completion keeps entry offset at cursor', eval_completion.entry_offset, 8)
support.expect_equal('dapui eval completion inserts after dot', eval_completion.insert_start, 7)
support.expect_equal('dapui eval completion first label', eval_completion.label, 'getName() : String')

-- Open init.lua in a window first so the jump target exists
vim.cmd('edit ' .. mock_source_path)

support.feed('<Space>dB')

local condition_buf = vim.api.nvim_get_current_buf()
support.expect_equal('conditional breakpoint filetype tracks source buffer', vim.bo[condition_buf].filetype, 'lua')
support.expect_true('conditional breakpoint includes dap source', vim.tbl_contains(current_source_names(), 'dap'))
support.expect_true('conditional breakpoint includes lsp source', vim.tbl_contains(current_source_names(), 'nvim_lsp'))

local condition_completion = run_dap_source_completion(condition_buf, 'user.')
support.expect_equal('conditional breakpoint completion request text', condition_completion.request.text, 'user.')
support.expect_equal('conditional breakpoint completion request column', condition_completion.request.column, 6)
support.expect_equal('conditional breakpoint completion returns fresh entries', condition_completion.entry_count, 2)
support.expect_equal('conditional breakpoint completion keeps request offset at cursor', condition_completion.request_offset, 6)
support.expect_equal('conditional breakpoint completion keeps entry offset at cursor', condition_completion.entry_offset, 6)
support.expect_equal('conditional breakpoint completion inserts after dot', condition_completion.insert_start, 5)
support.expect_equal('conditional breakpoint completion first label', condition_completion.label, 'getName() : String')

local partial_completion = run_dap_source_completion(condition_buf, 'user.ge')
support.expect_equal('conditional breakpoint partial completion request text', partial_completion.request.text, 'user.ge')
support.expect_equal('conditional breakpoint partial completion request column', partial_completion.request.column, 8)
support.expect_equal('conditional breakpoint partial completion returns fresh entries', partial_completion.entry_count, 2)
support.expect_equal('conditional breakpoint partial completion keeps request offset at member suffix', partial_completion.request_offset, 6)
support.expect_equal('conditional breakpoint partial completion keeps entry offset at member suffix', partial_completion.entry_offset, 6)
support.expect_equal('conditional breakpoint partial completion starts replacing typed suffix', partial_completion.insert_start, 5)
support.expect_equal('conditional breakpoint partial completion ends replacing typed suffix', partial_completion.insert_end, 7)
support.expect_equal('conditional breakpoint partial completion first label', partial_completion.label, 'getEmail() : String')

local expression_completion = run_dap_source_completion(condition_buf, 'foo + ge')
support.expect_equal('conditional breakpoint expression completion request text', expression_completion.request.text, 'foo + ge')
support.expect_equal('conditional breakpoint expression completion request column', expression_completion.request.column, 9)
support.expect_equal('conditional breakpoint expression completion returns fresh entries', expression_completion.entry_count, 2)
support.expect_equal('conditional breakpoint expression completion starts replacing typed suffix', expression_completion.insert_start, 6)
support.expect_equal('conditional breakpoint expression completion ends replacing typed suffix', expression_completion.insert_end, 8)
support.expect_equal('conditional breakpoint expression completion first label', expression_completion.label, 'getResult() : String')

local dollar_completion = run_dap_source_completion(condition_buf, 'this$')
support.expect_equal('conditional breakpoint dollar completion request text', dollar_completion.request.text, 'this$')
support.expect_equal('conditional breakpoint dollar completion request column', dollar_completion.request.column, 6)
support.expect_equal('conditional breakpoint dollar completion returns fresh entries', dollar_completion.entry_count, 2)
support.expect_equal('conditional breakpoint dollar completion starts at identifier head', dollar_completion.insert_start, 0)
support.expect_equal('conditional breakpoint dollar completion replaces full typed identifier', dollar_completion.insert_end, 5)
support.expect_equal('conditional breakpoint dollar completion first label', dollar_completion.label, 'this$0 : UserServiceImpl')
local dollar_auto_completion = run_dap_source_completion(condition_buf, 'this$', cmp.ContextReason.Auto, true)
support.expect_equal('conditional breakpoint dollar auto completion still issues request', dollar_auto_completion.request.text, 'this$')

local unicode_completion = run_dap_source_completion(condition_buf, '用户.ge')
support.expect_equal('conditional breakpoint unicode completion request text', unicode_completion.request.text, '用户.ge')
support.expect_equal('conditional breakpoint unicode completion request column uses utf16 units', unicode_completion.request.column, 6)
support.expect_equal('conditional breakpoint unicode completion returns fresh entries', unicode_completion.entry_count, 2)
support.expect_equal('conditional breakpoint unicode completion first label', unicode_completion.label, 'getDisplayName() : String')

local unicode_member_completion = run_dap_source_completion(condition_buf, '用户.显')
support.expect_equal('conditional breakpoint unicode member completion request text', unicode_member_completion.request.text, '用户.显')
support.expect_equal('conditional breakpoint unicode member completion request column uses utf16 units', unicode_member_completion.request.column, 5)
support.expect_equal('conditional breakpoint unicode member completion returns fresh entries', unicode_member_completion.entry_count, 2)
support.expect_equal('conditional breakpoint unicode member completion first label', unicode_member_completion.label, '显示名() : String')
support.expect_true('conditional breakpoint unicode member completion replaces typed suffix', unicode_member_completion.insert_end > unicode_member_completion.insert_start)
local unicode_member_auto_completion = run_dap_source_completion(condition_buf, '用户.显', cmp.ContextReason.Auto, true)
support.expect_equal('conditional breakpoint unicode member auto completion still issues request', unicode_member_auto_completion.request.text, '用户.显')
support.feed('<Esc>')

-- Open DAP UI Stacks buffer and render
dapui.open()

-- Wait for dapui to register all its listeners (3 threads, 8 scopes listeners)
local ok_listeners = vim.wait(2000, function()
  local threads_c = vim.tbl_count(dap.listeners.after["threads"] or {})
  local scopes_c = vim.tbl_count(dap.listeners.after["scopes"] or {})
  return threads_c >= 3 and scopes_c >= 8
end)
support.expect_true('dapui listeners registered', ok_listeners)

-- Trigger threads and scopes listeners to populate the components and force a render
local threads_count = 0
for name, cb in pairs(dap.listeners.after["threads"] or {}) do
  threads_count = threads_count + 1
  pcall(cb, mock_session, nil, { threads = { { id = 1, name = "main" } } }, nil, nil)
end
local scopes_count = 0
for name, cb in pairs(dap.listeners.after["scopes"] or {}) do
  scopes_count = scopes_count + 1
  pcall(cb, mock_session, nil, { { id = 1, name = "Local", variablesReference = 1 } }, nil, nil)
end
print("Threads listeners executed:", threads_count)
print("Scopes listeners executed:", scopes_count)

-- Locate Stacks buffer
local buf = nil
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[b].filetype == 'dapui_stacks' then
    buf = b
    break
  end
end

support.expect_true('dapui_stacks buffer created', buf ~= nil)

-- Wait for UI rendering (until stacks buffer is populated with lines)
local ok_render = vim.wait(2000, function()
  return vim.api.nvim_buf_line_count(buf) >= 2
end)
support.expect_true('dapui_stacks rendered lines', ok_render)

print("Wait render result:", ok_render, "Line count:", vim.api.nvim_buf_line_count(buf))
print("Buffer lines:")
for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
  print("  " .. vim.inspect(line))
end

-- Locate Stacks window and move cursor to line 2 (the frame line)
local stacks_win = nil
for _, win in ipairs(vim.api.nvim_list_wins()) do
  if vim.api.nvim_win_get_buf(win) == buf then
    stacks_win = win
    break
  end
end
support.expect_true('dapui_stacks window open', stacks_win ~= nil)

vim.api.nvim_set_current_win(stacks_win)
vim.api.nvim_win_set_cursor(stacks_win, { 2, 0 })

-- Trigger Enter keypress
support.feed('<CR>')

-- Wait for jump to finish (until active buffer is init.lua)
local ok_jump = vim.wait(2000, function()
  local cur_win = vim.api.nvim_get_current_win()
  local cur_buf = vim.api.nvim_win_get_buf(cur_win)
  local cur_name = vim.api.nvim_buf_get_name(cur_buf)
  print("Active buffer name: " .. cur_name)
  return cur_name:find("init.lua") ~= nil
end)
support.expect_true('jumped in time', ok_jump)

local final_win = vim.api.nvim_get_current_win()
local final_buf = vim.api.nvim_win_get_buf(final_win)
local final_cursor = vim.api.nvim_win_get_cursor(final_win)

support.expect_true('jumped to init.lua', vim.api.nvim_buf_get_name(final_buf):find("init.lua") ~= nil)
support.expect_equal('cursor is on line 10', final_cursor[1], 10)

support.flush()
