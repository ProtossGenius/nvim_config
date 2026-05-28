-- [[ user.plugins ]]
-- List of plugins for lazy.nvim

local is_nvim_012_or_newer = vim.fn.has('nvim-0.12') == 1

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
            { '<leader>L', group = 'LLM' },
            { '<leader>l', group = 'LSP' },
            { '<leader>m', group = 'Make/Build' },
            { '<leader>p', group = 'Project' },
            { '<leader>t', group = 'Toggle' },
            { '<leader>w', group = 'Window' },
            { '<leader>x', group = 'Diagnostics' },
          },
          {
            mode = 'n',
            { '<leader>d', group = 'Debug/Doc' },
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
      local project = require('user.project')
      local uv = vim.uv or vim.loop

      local function existing_ignore_files()
        local files = {}
        local candidates = {
          vim.fs.joinpath(vim.fn.stdpath('config'), '.nvimignore'),
          vim.fs.joinpath(vim.fn.getcwd(), '.nvimignore'),
        }

        for _, path in ipairs(candidates) do
          local stat = uv.fs_stat(path)
          if stat and stat.type == 'file' then
            table.insert(files, path)
          end
        end

        return files
      end

      local function find_all_files_command()
        local command = {
          'rg',
          '--files',
          '--hidden',
          '--follow',
          '--color',
          'never',
          '--no-ignore-vcs',
          '--no-ignore-parent',
          '--no-ignore-dot',
          '--no-ignore-exclude',
          '--glob',
          '!.git',
          '--glob',
          '!.git/**',
          '--glob',
          '!target',
          '--glob',
          '!target/**',
          '--glob',
          '!*.class',
        }

        for _, ignore_file in ipairs(existing_ignore_files()) do
          vim.list_extend(command, { '--ignore-file', ignore_file })
        end

        return command
      end

      local find_all_files = function()
        builtin.find_files({
          find_command = find_all_files_command(),
        })
      end

      require('project_nvim').setup({
        detection_methods = { 'pattern' },
        patterns = project.root_markers,
        silent_chdir = true,
      })
      telescope.load_extension('projects')

      vim.keymap.set('n', '<c-p>', find_all_files, { desc = 'Find files (including ignored)' })
      vim.keymap.set('n', '<A-f>', builtin.live_grep, { desc = 'Live Grep' })
      vim.keymap.set('n', '<A-r>', builtin.buffers, { desc = 'Find buffers' })
      vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = 'Help tags' })
      vim.keymap.set('n', '<leader>ff', builtin.git_files, { desc = 'Find git files' })
      vim.keymap.set('n', '<leader>fa', find_all_files, { desc = 'Find files (including ignored)' })
    end,
  },

  -- Syntax Highlighting
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'master',
    lazy = false,
    build = ':TSUpdate',
    config = function()
      local ok, configs = pcall(require, 'nvim-treesitter.configs')
      if not ok then
        vim.schedule(function()
          vim.notify(
            'nvim-treesitter is not installed yet. Run :Lazy sync to install/update plugins.',
            vim.log.levels.WARN
          )
        end)
        return
      end

      configs.setup {
        ensure_installed = {
          'bash',
          'c',
          'cpp',
          'go',
          'html',
          'java',
          'javascript',
          'json',
          'json5',
          'lua',
          'python',
          'rust',
          'toml',
          'tsx',
          'typescript',
          'xml',
          'yaml',
        },
        sync_install = false,
        auto_install = true,
        highlight = { enable = not is_nvim_012_or_newer },
        indent = { enable = not is_nvim_012_or_newer },
      }
    end,
  },
  {
    'windwp/nvim-ts-autotag',
    lazy = false,
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
    },
    opts = {
      opts = {
        enable_close = true,
        enable_rename = true,
        enable_close_on_slash = false,
      },
    },
  },

  -- Commenting
  {
    'JoosepAlviste/nvim-ts-context-commentstring',
    lazy = false,
    opts = {
      enable_autocmd = false,
    },
  },
  {
    'numToStr/Comment.nvim',
    lazy = false,
    dependencies = {
      'JoosepAlviste/nvim-ts-context-commentstring',
    },
    config = function()
      require('Comment').setup({
        pre_hook = require('user.comment').commentstring_pre_hook,
      })
    end,
  },
  {
    'kana/vim-textobj-user',
    lazy = false,
  },
  {
    'glts/vim-textobj-comment',
    lazy = false,
    dependencies = {
      'kana/vim-textobj-user',
    },
    config = function()
      local comment = require('user.comment')

      vim.keymap.set({ 'o', 'x' }, 'ac', comment.select_around, { desc = 'Select comment' })
      vim.keymap.set({ 'o', 'x' }, 'ic', comment.select_inner, { desc = 'Select inner comment' })
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
      local user_java = require('user.java')
      local user_dap_snippets = require('user.dap_snippets')
      local user_lsp = require('user.lsp')
      local capabilities = require('cmp_nvim_lsp').default_capabilities()

      require('java').setup(user_java.java_setup_config())
      user_java.setup()

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
      user_dap_snippets.setup()

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
          'rust_analyzer',
        },
        handlers = {
          lsp.default_setup,
          jdtls = function() end,
        },
      })

      vim.lsp.config('jdtls', vim.tbl_deep_extend('force', {
        capabilities = capabilities,
        on_attach = on_attach,
      }, user_java.jdtls_config(user_lsp.jdtls_settings())))
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
    dependencies = is_nvim_012_or_newer and {
      "nvim-tree/nvim-web-devicons",
    } or {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      require('aerial').setup({})
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
  {
    'mattn/emmet-vim',
    init = function()
      vim.g.user_emmet_install_global = 0
      vim.g.user_emmet_leader_key = ','
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('UserEmmetInstall', { clear = true }),
        pattern = {
          'css',
          'html',
          'svg',
          'xhtml',
          'xml',
        },
        callback = function()
          vim.cmd('EmmetInstall')
        end,
      })
    end,
  },
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
