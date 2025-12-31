-- [[ user.plugins ]]
-- List of plugins for lazy.nvim

return {
  -- Colorscheme
  {
    'ellisonleao/gruvbox.nvim',
    priority = 1000,
    config = function()
      vim.cmd.colorscheme 'gruvbox'
      vim.o.background = 'dark'
    end,
  },

  -- Statusline
  {
    'nvim-lualine/lualine.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function()
      require('lualine').setup {
        options = {
          theme = 'gruvbox',
          icons_enabled = true,
          component_separators = { left = '', right = '' },
          section_separators = { left = '', right = '' },
        },
      }
    end,
  },

  -- Fuzzy Finder
  {
    'nvim-telescope/telescope.nvim',
    tag = '0.1.5',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      local builtin = require('telescope.builtin')
      vim.keymap.set('n', '<c-p>', function()
        builtin.find_files({ hidden = true })
      end, { desc = 'Find files (including hidden)' })
      vim.keymap.set('n', '<A-f>', builtin.live_grep, { desc = 'Live Grep' })
      vim.keymap.set('n', '<A-r>', builtin.buffers, { desc = 'Find buffers' })
      vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = 'Help tags' })
      vim.keymap.set('n', '<leader>ff', builtin.git_files, { desc = 'Find git files' })
    end,
  },

  -- Syntax Highlighting
  {
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    config = function()
      require('nvim-treesitter.configs').setup {
        ensure_installed = { 'c', 'cpp', 'go', 'lua', 'python', 'rust', 'javascript', 'typescript', 'java' },
        sync_install = false,
        auto_install = true,
        highlight = { enable = true },
        indent = { enable = true },
      }
    end,
  },

  -- LSP, Autocompletion
  {
    'VonHeikemen/lsp-zero.nvim',
    branch = 'v3.x',
    dependencies = {
      -- LSP Support
      { 'neovim/nvim-lspconfig' },
      { 'williamboman/mason.nvim' },
      { 'williamboman/mason-lspconfig.nvim' },

      -- Autocompletion
      { 'hrsh7th/nvim-cmp' },
      { 'hrsh7th/cmp-nvim-lsp' },
      { 'hrsh7th/cmp-buffer' },
      { 'hrsh7th/cmp-path' },
      { 'saadparwaiz1/cmp_luasnip' },
      { 'hrsh7th/cmp-nvim-lua' },

      -- Snippets
      { 'L3MON4D3/LuaSnip' },
      { 'rafamadriz/friendly-snippets' },
    },
    config = function()
      local luasnip = require('luasnip')
      local lsp = require('lsp-zero').preset({})

      -- 加载本地代码片段的辅助函数
      local function load_local_snippets()
        local cwd = vim.fn.getcwd()
        local local_snippets = cwd .. "/.snippets"
        if vim.fn.isdirectory(local_snippets) == 1 then
          require("luasnip.loaders.from_lua").lazy_load({ paths = { local_snippets } })
        end
      end

      -- 初始化时加载一次
      load_local_snippets()

      -- 当切换目录或进入新 buffer 时尝试再次加载
      vim.api.nvim_create_autocmd({ "DirChanged", "BufEnter" }, {
        callback = function()
          load_local_snippets()
        end,
      })

      lsp.on_attach(function(client, bufnr)
        lsp.default_keymaps({ buffer = bufnr })
        vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = bufnr, desc = 'Go to Definition' })
        vim.keymap.set('n', 'gr', vim.lsp.buf.references, { buffer = bufnr, desc = 'Go to References' })
        vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, { buffer = bufnr, desc = 'Go to Declaration' })
        vim.keymap.set('n', 'K', vim.lsp.buf.hover, { buffer = bufnr, desc = 'Hover' })
        vim.keymap.set('n', 'ff', vim.lsp.buf.code_action, { buffer = bufnr, desc = 'Code Action' })
        vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, { buffer = bufnr, desc = 'Rename' })
      end)

      -- Let lsp-zero manage mason and server setup
      require('mason').setup({})
      require('mason-lspconfig').setup({
        ensure_installed = {
          'clangd',
          'ts_ls',
          'gopls',
          'jdtls',
          'rust_analyzer',
        },
        handlers = {
          lsp.default_setup,
        },
      })

      -- Setup completion
      local cmp = require('cmp')
      local cmp_select = { behavior = cmp.SelectBehavior.Select }
      cmp.setup({
        sources = {
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
          { name = 'buffer' },
          { name = 'path' },
        },
        snippet = {
          expand = function(args)
            require('luasnip').lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ['<C-p>'] = cmp.mapping.select_prev_item(cmp_select),
          ['<C-n>'] = cmp.mapping.select_next_item(cmp_select),
          ['<C-y>'] = cmp.mapping.confirm({ select = true }),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.confirm({ select = true })
            elseif luasnip.expand_or_locally_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { 'i', 's' }),
          ['<S-Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item(cmp_select)
            elseif luasnip.locally_jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { 'i', 's' }),
        }),
      })
    end,
  },

  -- Git integration
  {
    'lewis6991/gitsigns.nvim',
    config = function()
      require('gitsigns').setup()
    end,
  },

  -- Auto-closing pairs
  {
    'windwp/nvim-autopairs',
    event = "InsertEnter",
    config = true,
  },

  -- Code outline
  {
    'stevearc/aerial.nvim',
    opts = {},
    -- Optional dependencies
    dependencies = {
       "nvim-treesitter/nvim-treesitter",
       "nvim-tree/nvim-web-devicons"
    },
    config = function()
      require('aerial').setup({
        -- optionally use on_attach to set keymaps when aerial has attached to a buffer
        on_attach = function(bufnr)
          -- Jump forwards/backwards with '{' and '}'
          vim.keymap.set('n', '{', '<cmd>AerialPrev<CR>', {buffer = bufnr})
          vim.keymap.set('n', '}', '<cmd>AerialNext<CR>', {buffer = bufnr})
        end
      })
    end
  },

  -- File Explorer (Dirvish)
  {
    'justinmk/vim-dirvish',
    config = function()
      vim.cmd('let g:dirvish_hide_gitignore = 1')
      vim.cmd('let g:dirvish_hide_netrw = 1')
    end,
  },

  -- Kept from your original config
  'voldikss/vim-translator',
  'junegunn/vim-easy-align',
  'fatih/vim-go',
  'tpope/vim-unimpaired',
  'tpope/vim-surround',
  'mattn/emmet-vim',
  'ProtossGenius/leetcode.vim',

  -- Markdown Preview
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    build = "cd app && npx --yes yarn install",
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
    end,
    ft = { "markdown" },
  },
  {
  'ray-x/lsp_signature.nvim',
  event = 'InsertEnter', -- 在进入插入模式时加载
  config = function()
    require('lsp_signature').setup({
      bind = true, -- 在输入时自动显示签名帮助
      handler_opts = {
        border = 'rounded', -- 浮动窗口边框
      },
      -- 其他配置项...
    })
  end
},
}
