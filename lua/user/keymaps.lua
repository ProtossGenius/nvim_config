-- [[ user.keymaps ]]
-- Keymaps

local opts = { noremap = true, silent = true }
local keymap = vim.keymap.set

-- Insert Mode
keymap('i', 'jj', '<ESC>', opts)
-- 在终端模式下，将 jj 映射为退出终端模式
vim.api.nvim_set_keymap('t', 'jj', '<C-\\><C-n>', { noremap = true, silent = true, desc = 'Exit terminal mode to Normal' })
-- Normal Mode
-- Save buffer
keymap({ 'i', 'n', 'v' }, '<C-s>', '<cmd>w<cr><esc>', { desc = 'Save file' })

-- File Explorer
-- keymap('n', '-', '<cmd>Dirvish<cr>', { desc = 'Open Dirvish' })

-- Window Navigation
keymap('n', '<leader><Right>', '<C-w>l', { desc = 'Move to right window' })
keymap('n', '<leader><Left>', '<C-w>h', { desc = 'Move to left window' })
keymap('n', '<leader><Up>', '<C-w>k', { desc = 'Move to upper window' })
keymap('n', '<leader><Down>', '<C-w>j', { desc = 'Move to lower window' })
keymap('n', '<leader>sv', '<cmd>vsplit<cr>', { desc = 'Split window vertically' })

-- Diagnostics (replaces ALE bindings)
keymap({'n', 'i'}, '<M-n>', vim.diagnostic.goto_next, { desc = 'Next diagnostic' })
keymap({'n', 'i'}, '<M-p>', vim.diagnostic.goto_prev, { desc = 'Previous diagnostic' })
keymap('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Show diagnostic error' })

-- Git Changes
keymap('n', ']c', '<cmd>Gitsigns next_hunk<cr>', { desc = 'Next Git change' })
keymap('n', '[c', '<cmd>Gitsigns prev_hunk<cr>', { desc = 'Previous Git change' })

-- Telescope (replaces LeaderF bindings)
keymap('n', '<C-n>', '<cmd>Telescope oldfiles<cr>', { desc = 'Find recent files' })
keymap('n', '<leader>p', '<cmd>Telescope projects<cr>', { desc = 'Find projects' }) -- Needs telescope-project.nvim
keymap('n', '<leader>ds', '<cmd>Telescope lsp_document_symbols<cr>', { desc = 'Document symbols' })
keymap('n', '<leader>ts', '<cmd>Telescope tags<cr>', { desc = 'Find tags' })

-- Terminal
-- Terminal toggle (Alt-t)
keymap({'n', 'i', 'v', 't'}, '<M-t>', function()
  local terminal_buffers = {}
  local visible_terminal_winid = nil

  -- Find all terminal buffers and check for visible terminals
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_option(bufnr, 'buftype') == 'terminal' then
      table.insert(terminal_buffers, bufnr)
      -- Check if this terminal buffer is currently visible in any window
      for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(winid) == bufnr then
          visible_terminal_winid = winid
          break
        end
      end
    end
  end

  if visible_terminal_winid then
    -- If a terminal is visible, hide it (close its window)
    vim.api.nvim_win_close(visible_terminal_winid, true)
  else
    local win_opts = {
      relative = 'editor',
      width = vim.o.columns,
      height = vim.o.lines,
      col = 0,
      row = 0,
      style = 'minimal',
      border = 'none',
      zindex = 50,
    }
    if #terminal_buffers > 0 then
      -- If terminals exist but none are visible, show the first one in a fullscreen float
      vim.api.nvim_open_win(terminal_buffers[1], true, win_opts)
      vim.cmd('startinsert!') -- Enter insert mode automatically
    else
      -- No terminals exist, create a new one in a fullscreen float
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_open_win(buf, true, win_opts)
      vim.cmd('terminal')
      vim.cmd('startinsert!') -- Enter insert mode automatically
    end
  end
end, { desc = 'Toggle terminal' })

-- Better movement
keymap('n', 'j', 'gj')
keymap('n', 'k', 'gk')

-- Compile and Run commands
-- Helper function to run commands in a terminal
local function term_exec(cmd)
  vim.cmd('wa')
  vim.cmd('terminal ' .. cmd)
end
keymap('v', '<C-c>', 'y')
keymap('n', '<S-f>', 'gF')
keymap('n', '<F5>', function() term_exec('make qrun') end, { desc = 'Make qrun' })
keymap('n', '<F6>', function() term_exec('make') end, { desc = 'Make' })
keymap('n', '<F8>', function() term_exec('make tests') end, { desc = 'Make tests' })
keymap('n', '<F9>', function() term_exec('make debug') end, { desc = 'Make debug' })

-- C/C++ Header/Source toggle
keymap('n', '<M-h>', function() require('user.util').toggle_header_source() end, { desc = 'Toggle header/source' })

-- Aerial (Code Outline)
keymap('n', '<leader>a', '<cmd>AerialToggle! left<cr>', { desc = 'Toggle Aerial outline' })

-- Go plugin mappings (from vim-go)
-- These will work because fatih/vim-go is installed
keymap('n', '<leader>gs', '<Plug>(go-implements)')
keymap('n', '<leader>gi', '<Plug>(go-info)')
keymap('n', '<leader>gr', '<Plug>(go-run)')
keymap('n', '<leader>gb', '<Plug>(go-build)')
keymap('n', '<leader>gt', '<Plug>(go-test)')
keymap('n', '<leader>rn', '<Plug>(go-rename)')

-- C/C++ Macro Expansion
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "c", "cpp" },
  callback = function()
    vim.keymap.set('i', ',mm', function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local line = vim.api.nvim_get_current_line()
      if cursor[2] >= 3 then
        local new_line = line:sub(1, cursor[2] - 3) .. line:sub(cursor[2] + 1)
        vim.api.nvim_set_current_line(new_line)
        vim.api.nvim_win_set_cursor(0, { cursor[1], cursor[2] - 3 })
      end
      require('user.util').expand_macro()
    end, { buffer = true, desc = 'Expand macro' })

    vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, { desc = "LSP 重命名" })
    vim.keymap.set('n', ',mm', function()
      require('user.util').expand_macro()
    end, { buffer = true, desc = 'Expand macro' })
  end,
})
