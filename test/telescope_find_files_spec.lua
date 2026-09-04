local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

local map = vim.fn.maparg('<C-p>', 'n', false, true)
support.expect_true('ctrl-p find files mapping has callback', type(map.callback) == 'function')

local ok, err = pcall(function()
  vim.defer_fn(function()
    pcall(require('telescope.actions').close, vim.api.nvim_get_current_buf())
  end, 200)
  map.callback()
  vim.wait(500)
end)

support.expect_true('ctrl-p find files opens without sync error', ok, err)

support.flush()
