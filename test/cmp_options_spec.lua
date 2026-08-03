local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

local completeopt = vim.opt.completeopt:get()

support.expect_true('completeopt keeps menu completion enabled', vim.tbl_contains(completeopt, 'menu'))
support.expect_true('completeopt keeps single-item menu enabled', vim.tbl_contains(completeopt, 'menuone'))
support.expect_true('completeopt avoids preinserting selected item text', vim.tbl_contains(completeopt, 'noinsert'))
support.expect_true('completeopt keeps noselect behavior', vim.tbl_contains(completeopt, 'noselect'))

support.flush()
