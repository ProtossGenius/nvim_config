-- [[ init.lua ]]

-- Set <space> as the leader key
-- See `:help mapleader`
--  NOTE: Must happen before plugins are required (otherwise wrong leader will be used)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

vim.opt.encoding = "utf-8"
vim.opt.fileencodings = "ucs-bom,utf-8,gb18030,cp936,gbk,big5,latin1"
-- Install package manager
--    https://github.com/folke/lazy.nvim
--    `:help lazy.nvim.txt` for more info
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system {
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable', -- latest stable release
    lazypath,
  }
end
vim.opt.rtp:prepend(lazypath)

-- Load user configurations
require('user.options')
require('user.keymaps')

-- Load plugins
require('lazy').setup('user.plugins', {
  checker = {
    enabled = true,
    notify = false,
  },
  change_detection = {
    notify = false,
  },
})

-- Load utility functions
require('user.util')

-- Fcitx input method switching
local fcitx_status = ""
vim.api.nvim_create_autocmd("InsertLeave", {
  callback = function()
    local handle = io.popen("fcitx-remote")
    local status = handle:read("*a")
    handle:close()
    if string.match(status, "^2") then -- Fcitx status 2 means active Chinese IME
      fcitx_status = "zh"
    else
      fcitx_status = "en"
    end
    vim.fn.system("fcitx-remote -c") -- Switch to English
  end,
})

vim.api.nvim_create_autocmd("InsertEnter", {
  callback = function()
    if fcitx_status == "zh" then
      vim.fn.system("fcitx-remote -o") -- Switch back to Chinese
    end
    fcitx_status = "" -- Reset status
  end,
})
