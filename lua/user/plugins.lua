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

  {
    'folke/which-key.nvim',
    event = 'VeryLazy',
    config = function()
      local wk = require('which-key')

      wk.setup({
        preset = 'classic',
        delay = 200,
        win = {
          border = 'rounded',
          no_overlap = false,
          row = math.huge,
          col = 0,
          padding = { 1, 2 },
        },
        layout = {
          width = { min = 24 },
          spacing = 3,
        },
        spec = {
          {
            mode = { 'n', 'v' },
            { '<leader>b', group = 'Buffer' },
            { '<leader>f', group = 'Find/File' },
            { '<leader>g', group = 'Git' },
            { '<leader>j', group = 'Java' },
            { '<leader>l', group = 'LSP' },
            { '<leader>m', group = 'Make/Build' },
            { '<leader>p', group = 'Project' },
            { '<leader>t', group = 'Toggle' },
            { '<leader>w', group = 'Window' },
            { '<leader>x', group = 'Diagnostics' },
          },
          {
            mode = 'n',
            { '<leader>d', group = 'Document' },
            { '<leader>o', group = 'Open/Outline' },
            { '<leader>r', group = 'Rename' },
            { '<leader>s', group = 'Split' },
            {
              '<leader>?',
              function()
                wk.show({ global = false })
              end,
              desc = 'Buffer local keymaps',
            },
          },
          {
            mode = 'v',
            { '<leader>o', group = 'Ollama' },
            { '<leader>ot', desc = 'Translate selection with Ollama' },
          },
        },
      })
    end,
  },

  -- Fuzzy Finder
  {
    'nvim-telescope/telescope.nvim',
    tag = '0.1.5',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'ahmedkhalf/project.nvim',
    },
    config = function()
      local telescope = require('telescope')
      local builtin = require('telescope.builtin')

      require('project_nvim').setup({
        detection_methods = { 'pattern' },
        patterns = {
          '.git',
          'mvnw',
          'gradlew',
          'pom.xml',
          'build.gradle',
          'build.gradle.kts',
          'settings.gradle',
          'settings.gradle.kts',
          'Makefile',
          'package.json',
        },
        silent_chdir = true,
      })
      telescope.load_extension('projects')

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
      { 'nvim-java/nvim-java' },
      { 'MunifTanjim/nui.nvim' },
      { 'mfussenegger/nvim-dap' },
      { 'JavaHello/spring-boot.nvim', commit = '218c0c26c14d99feca778e4d13f5ec3e8b1b60f0' },

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
      local user_lsp = require('user.lsp')
      local capabilities = require('cmp_nvim_lsp').default_capabilities()

      require('java').setup({
        lombok = {
          enable = true,
        },
      })

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

      local function on_attach(client, bufnr)
        lsp.default_keymaps({ buffer = bufnr })
        user_lsp.on_attach(client, bufnr)
      end

      lsp.on_attach(on_attach)

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
          jdtls = function() end,
        },
      })

      local lombok_jar = vim.fn.stdpath('data') .. '/mason/packages/jdtls/lombok.jar'
      vim.lsp.config('jdtls', {
        cmd = {
          vim.fn.stdpath('data') .. '/mason/bin/jdtls',
          '--jvm-arg=-javaagent:' .. lombok_jar,
        },
        capabilities = capabilities,
        on_attach = on_attach,
        settings = user_lsp.jdtls_settings(),
      })
      vim.lsp.enable('jdtls')

      -- Setup completion
      local cmp = require('cmp')
      local cmp_select = { behavior = cmp.SelectBehavior.Select }
      cmp.setup({
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
        }, {
          { name = 'buffer' },
          { name = 'path' },
        }),
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
--  {
--    'fatih/vim-go',
--    config = function()
--      vim.g.go_fmt_autosave = 0
--      vim.g.go_imports_autosave = 0
--    end
--  },
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
