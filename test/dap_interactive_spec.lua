local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

-- Wait for lazy.nvim to finish loading plugins (e.g. nvim-cmp, nvim-dap-ui)
require('lazy').load({ plugins = { 'nvim-cmp', 'nvim-dap', 'nvim-dap-ui', 'nvim-nio' } })

local cmp = require('cmp')
local dap = require('dap')

-- 1. Mock DAP session first before anything else loads dapui client
local mock_source_path = vim.fn.stdpath('config') .. "/init.lua"
local mock_session = {
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
  capabilities = {},
  _frame_set = function(self, frame)
    self.current_frame = frame
  end,
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
vim.bo[dummy_buf].filetype = 'dap-repl'
vim.api.nvim_set_current_buf(dummy_buf)
support.expect_true('cmp enabled in dap-repl', cmp.get_config().enabled())

local watches_buf = vim.api.nvim_create_buf(false, true)
vim.bo[watches_buf].buftype = 'prompt'
vim.bo[watches_buf].filetype = 'dapui_watches'
vim.api.nvim_set_current_buf(watches_buf)
support.expect_true('cmp enabled in dapui_watches', cmp.get_config().enabled())

-- Open init.lua in a window first so the jump target exists
vim.cmd('edit ' .. mock_source_path)

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
