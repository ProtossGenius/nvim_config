-- [[ user.options ]]
-- Neovim options

local opt = vim.opt

-- Tabs and Indentation
opt.tabstop = 2
opt.shiftwidth = 2
opt.softtabstop = 2
opt.expandtab = true
opt.autoindent = true
opt.smartindent = true

-- Search
opt.hlsearch = true
opt.incsearch = true
opt.ignorecase = true
opt.smartcase = true

-- Appearance
opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.cursorcolumn = true
opt.splitbelow = true
opt.splitright = true
opt.termguicolors = true
opt.title = true
opt.laststatus = 3 -- Global statusline
opt.signcolumn = 'yes'

-- Behavior
opt.backspace = 'indent,eol,start'
opt.clipboard = 'unnamedplus' -- Use system clipboard
opt.completeopt = 'menu,menuone,noselect'
opt.hidden = true
opt.mouse = 'a'
opt.scrolloff = 8 -- Lines of context around the cursor
opt.sidescrolloff = 8
opt.wrap = false -- Disable line wrapping

-- Performance
opt.updatetime = 250 -- Faster updates (e.g., for git signs)
opt.undofile = true -- Persistent undo
