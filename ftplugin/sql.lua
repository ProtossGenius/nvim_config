-- ftplugin/sql.lua
local ok, cmp = pcall(require, 'cmp')

-- SQL 补全：使用 buffer/path/luasnip 源，不依赖 dbext 插件
if ok then
  cmp.setup.buffer {
    sources = cmp.config.sources({
      { name = 'nvim_lsp' },
      { name = 'luasnip' },
    }, {
      {
        name = 'buffer',
        option = {
          get_bufnrs = function()
            return vim.api.nvim_list_bufs()
          end
        }
      },
      { name = 'path' },
    })
  }
end
