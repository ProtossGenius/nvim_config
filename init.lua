-- [[ init.lua ]]

-- Set <space> as the leader key
-- See `:help mapleader`
--  NOTE: Must happen before plugins are required (otherwise wrong leader will be used)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

require('user.audit').setup()

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

if vim.fn.has('nvim-0.12') == 1 then
  local original_treesitter_start = vim.treesitter.start
  local builtin_ts_filetypes = {
    bash = 'bash',
    c = 'c',
    cpp = 'cpp',
    go = 'go',
    html = 'html',
    java = 'java',
    javascript = 'javascript',
    javascriptreact = 'javascript',
    lua = 'lua',
    python = 'python',
    rust = 'rust',
    sh = 'bash',
    typescript = 'typescript',
    typescriptreact = 'tsx',
    xml = 'xml',
  }

  -- Neovim 0.12 ftplugins may call vim.treesitter.start() even when no parser is available.
  -- Guard that path so WSL or minimal installs do not error during startup or file open.
  vim.treesitter.start = function(bufnr, lang)
    bufnr = bufnr or 0
    local resolved_lang = lang

    if not resolved_lang then
      local filetype = vim.bo[bufnr].filetype
      resolved_lang = vim.treesitter.language.get_lang(filetype) or filetype
    end

    if not resolved_lang or not pcall(vim.treesitter.language.inspect, resolved_lang) then
      return
    end

    return original_treesitter_start(bufnr, resolved_lang)
  end

  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('BuiltinTreesitter', { clear = true }),
    pattern = vim.tbl_keys(builtin_ts_filetypes),
    callback = function(args)
      vim.treesitter.start(args.buf, builtin_ts_filetypes[args.match])
    end,
  })
end

-- Load utility functions
require('user.util')
require('user.jump').setup()
require('user.dap').setup()
require('user.xml').setup()

-- Load file templates boilerplate generator
require('user.templates').setup()

-- Override global selection UI with premium floating menu
vim.ui.select = require('user.select').select

-- C/C++ printf highlighting
require('user.printf_highlight').setup()

-- Fcitx input method switching (skip if fcitx-remote is not installed)
if vim.fn.executable('fcitx-remote') == 1 then
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
end

-- macOS input method switching (skip if im-select is not installed)
if vim.fn.has('macunix') == 1 and vim.fn.executable('im-select') == 1 then
  local previous_input_source = nil
  local english_input_source = vim.g.mac_english_input_source or 'com.apple.keylayout.ABC'
  local notify_failed = false

  local function run_im_select(args)
    local output = vim.fn.system(vim.list_extend({ 'im-select' }, args or {}))
    if vim.v.shell_error ~= 0 then
      if not notify_failed then
        notify_failed = true
        vim.schedule(function()
          vim.notify('im-select failed to switch macOS input method.', vim.log.levels.WARN)
        end)
      end
      return nil
    end

    return vim.trim(output)
  end

  vim.api.nvim_create_autocmd("InsertLeave", {
    callback = function()
      local current_input_source = run_im_select()
      if not current_input_source or current_input_source == '' then
        return
      end

      if current_input_source ~= english_input_source then
        previous_input_source = current_input_source
        run_im_select({ english_input_source })
      else
        previous_input_source = nil
      end
    end,
  })

  vim.api.nvim_create_autocmd("InsertEnter", {
    callback = function()
      if previous_input_source and previous_input_source ~= english_input_source then
        run_im_select({ previous_input_source })
      end
      previous_input_source = nil
    end,
  })
end

-- 开启折行显示
vim.opt.wrap = true
-- 优化折行体验：不在单词中间断开
vim.opt.linebreak = true
-- 配合 linebreak，设置折行后的缩进与上一行对齐
vim.opt.breakindent = true
