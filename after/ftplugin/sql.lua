-- after/ftplugin/sql.lua
-- 在 Neovim 内置 sql.vim 之后执行，清除 omnifunc 避免 dbext 报错
vim.bo.omnifunc = ''
