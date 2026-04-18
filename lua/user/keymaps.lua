-- [[ user.keymaps ]]
-- Keymaps

local opts = { noremap = true, silent = true }
local keymap = vim.keymap.set

local function leader_map(mode, lhs, rhs, desc)
  keymap(mode, lhs, rhs, vim.tbl_extend('force', opts, { desc = desc }))
end

-- Insert Mode
keymap('i', 'jj', '<ESC>', opts)
-- 在终端模式下，将 jj 映射为退出终端模式
vim.api.nvim_set_keymap('t', 'jj', '<C-\\><C-n>', { noremap = true, silent = true, desc = 'Exit terminal mode to Normal' })
-- Normal Mode
-- Save buffer
keymap({ 'i', 'n', 'v' }, '<C-s>', '<cmd>w<cr><esc>', { desc = 'Save file' })
leader_map('n', '<leader>fs', '<cmd>w<cr>', 'Save file')

-- File Explorer
-- keymap('n', '-', '<cmd>Dirvish<cr>', { desc = 'Open Dirvish' })

-- Window Navigation
keymap('n', '<leader><Right>', '<C-w>l', { desc = 'Move to right window' })
keymap('n', '<leader><Left>', '<C-w>h', { desc = 'Move to left window' })
keymap('n', '<leader><Up>', '<C-w>k', { desc = 'Move to upper window' })
keymap('n', '<leader><Down>', '<C-w>j', { desc = 'Move to lower window' })
keymap('n', '<leader>sv', '<cmd>vsplit<cr>', { desc = 'Split window vertically' })
leader_map('n', '<leader>wh', '<C-w>h', 'Move to left window')
leader_map('n', '<leader>wj', '<C-w>j', 'Move to lower window')
leader_map('n', '<leader>wk', '<C-w>k', 'Move to upper window')
leader_map('n', '<leader>wl', '<C-w>l', 'Move to right window')
leader_map('n', '<leader>wv', '<cmd>vsplit<cr>', 'Split window vertically')

-- Diagnostics (replaces ALE bindings)
keymap({'n', 'i'}, '<M-n>', vim.diagnostic.goto_next, { desc = 'Next diagnostic' })
keymap({'n', 'i'}, '<M-p>', vim.diagnostic.goto_prev, { desc = 'Previous diagnostic' })
keymap('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Show diagnostic error' })
leader_map('n', '<leader>xn', vim.diagnostic.goto_next, 'Next diagnostic')
leader_map('n', '<leader>xp', vim.diagnostic.goto_prev, 'Previous diagnostic')
leader_map('n', '<leader>xe', vim.diagnostic.open_float, 'Show diagnostic error')

-- Enter diagnostic float window (press again or use <leader>xf to focus)
leader_map('n', '<leader>xf', function()
  local _, winid = vim.diagnostic.open_float({ focus = true })
  if winid then
    vim.api.nvim_set_current_win(winid)
  end
end, 'Focus diagnostic float')

-- Copy all diagnostics on current line to system clipboard
leader_map('n', '<leader>xy', function()
  local diagnostics = vim.diagnostic.get(0, { lnum = vim.api.nvim_win_get_cursor(0)[1] - 1 })
  if #diagnostics == 0 then
    vim.notify('No diagnostics on this line', vim.log.levels.INFO)
    return
  end
  local lines = {}
  for _, d in ipairs(diagnostics) do
    local severity = vim.diagnostic.severity[d.severity] or 'UNKNOWN'
    table.insert(lines, string.format('[%s] %s', severity, d.message))
  end
  local text = table.concat(lines, '\n')
  vim.fn.setreg('+', text)
  vim.notify(string.format('Copied %d diagnostic(s) to clipboard', #diagnostics), vim.log.levels.INFO)
end, 'Copy line diagnostics to clipboard')

-- Git Changes
keymap('n', ']c', '<cmd>Gitsigns next_hunk<cr>', { desc = 'Next Git change' })
keymap('n', '[c', '<cmd>Gitsigns prev_hunk<cr>', { desc = 'Previous Git change' })
leader_map('n', '<leader>gn', '<cmd>Gitsigns next_hunk<cr>', 'Next Git change')
leader_map('n', '<leader>gp', '<cmd>Gitsigns prev_hunk<cr>', 'Previous Git change')

-- Telescope (replaces LeaderF bindings)
keymap('n', '<C-n>', '<cmd>Telescope oldfiles<cr>', { desc = 'Find recent files' })
keymap('n', '<leader>p', '<cmd>Telescope projects<cr>', { desc = 'Find projects' })
keymap('n', '<leader>ds', '<cmd>Telescope lsp_document_symbols<cr>', { desc = 'Document symbols' })
keymap('n', '<leader>ts', '<cmd>Telescope tags<cr>', { desc = 'Find tags' })
leader_map('n', '<leader>fa', '<cmd>Telescope find_files hidden=true<cr>', 'Find files (including hidden)')
leader_map('n', '<leader>fb', '<cmd>Telescope buffers<cr>', 'Find buffers')
leader_map('n', '<leader>fg', '<cmd>Telescope live_grep<cr>', 'Live Grep')
leader_map('n', '<leader>fr', '<cmd>Telescope oldfiles<cr>', 'Find recent files')
leader_map('n', '<leader>ft', '<cmd>Telescope tags<cr>', 'Find tags')
leader_map('n', '<leader>pp', '<cmd>Telescope projects<cr>', 'Find projects')

-- Terminal
-- Terminal toggle (Alt-t)
local function toggle_terminal()
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
      height = vim.o.lines - 2,
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
end

keymap({'n', 'i', 'v', 't'}, '<M-t>', toggle_terminal, { desc = 'Toggle terminal' })
leader_map('n', '<leader>tt', toggle_terminal, 'Toggle terminal')

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
leader_map('n', '<leader>mr', function() term_exec('make qrun') end, 'Make qrun')
leader_map('n', '<leader>mm', function() term_exec('make') end, 'Make')
leader_map('n', '<leader>mt', function() term_exec('make tests') end, 'Make tests')
leader_map('n', '<leader>md', function() term_exec('make debug') end, 'Make debug')

-- C/C++ Header/Source toggle
keymap('n', '<M-h>', function() require('user.util').toggle_header_source() end, { desc = 'Toggle header/source' })
leader_map('n', '<leader>oh', function() require('user.util').toggle_header_source() end, 'Toggle header/source')

-- Aerial (Code Outline)
keymap('n', '<leader>a', '<cmd>AerialToggle! left<cr>', { desc = 'Toggle Aerial outline' })
leader_map('n', '<leader>oa', '<cmd>AerialToggle! left<cr>', 'Toggle Aerial outline')

-- Ollama translation
keymap('v', '<leader>ot', function()
  require('user.translate').translate_visual_selection()
end, { desc = 'Translate selection with Ollama' })

-- Go plugin mappings (kept for compatibility if vim-go is enabled again)
keymap('n', '<leader>gs', '<Plug>(go-implements)', { desc = 'Go implements' })
keymap('n', '<leader>gi', '<Plug>(go-info)', { desc = 'Go info' })
keymap('n', '<leader>gr', '<Plug>(go-run)', { desc = 'Go run' })
keymap('n', '<leader>gb', '<Plug>(go-build)', { desc = 'Go build' })
keymap('n', '<leader>gt', '<Plug>(go-test)', { desc = 'Go test' })
keymap('n', '<leader>rn', '<Plug>(go-rename)', { desc = 'Go rename' })

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
