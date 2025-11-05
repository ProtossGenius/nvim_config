-- [[ user.keymaps ]]
-- Keymaps

local opts = { noremap = true, silent = true }
local keymap = vim.keymap.set

-- Insert Mode
keymap('i', 'jj', '<ESC>', opts)

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
keymap('n', 'sn', vim.diagnostic.goto_next, { desc = 'Next diagnostic' })
keymap('n', 'sp', vim.diagnostic.goto_prev, { desc = 'Previous diagnostic' })
keymap('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Show diagnostic error' })

-- Telescope (replaces LeaderF bindings)
keymap('n', '<C-n>', '<cmd>Telescope oldfiles<cr>', { desc = 'Find recent files' })
keymap('n', '<leader>p', '<cmd>Telescope projects<cr>', { desc = 'Find projects' }) -- Needs telescope-project.nvim
keymap('n', '<leader>ds', '<cmd>Telescope lsp_document_symbols<cr>', { desc = 'Document symbols' })
keymap('n', '<leader>ts', '<cmd>Telescope tags<cr>', { desc = 'Find tags' })

-- Terminal
keymap('n', '<M-t>', '<cmd>split | terminal<cr>', { desc = 'Open terminal' })

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

-- Go plugin mappings (from vim-go)
-- These will work because fatih/vim-go is installed
keymap('n', '<leader>gs', '<Plug>(go-implements)')
keymap('n', '<leader>gi', '<Plug>(go-info)')
keymap('n', '<leader>gr', '<Plug>(go-run)')
keymap('n', '<leader>gb', '<Plug>(go-build)')
keymap('n', '<leader>gt', '<Plug>(go-test)')
keymap('n', '<leader>rn', '<Plug>(go-rename)')
