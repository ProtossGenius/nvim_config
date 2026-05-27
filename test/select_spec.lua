local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
local select = require('user.select')

local choice_item
local choice_index

local function open_select()
  choice_item = nil
  choice_index = nil
  select.select({ 'alpha', 'beta', 'gamma' }, { prompt = 'Test Select' }, function(item, index)
    choice_item = item
    choice_index = index
  end)
  vim.wait(100)
end

open_select()
support.expect_equal('select status line visible', vim.api.nvim_buf_get_lines(0, 0, 1, false), { ' Input: ' })
support.feed('2')
support.expect_equal('select numeric jump updates status', vim.api.nvim_buf_get_lines(0, 0, 1, false), { ' Input: 2' })
support.feed('<CR>')
support.expect_equal('select enter chooses item', { choice_item, choice_index }, { 'beta', 2 })

open_select()
local popup_buf = vim.api.nvim_get_current_buf()
support.feed('j')
local cursor_before_invalid = vim.api.nvim_win_get_cursor(0)
support.feed('9')
support.expect_equal('select invalid numeric input does not jump', vim.api.nvim_win_get_cursor(0), cursor_before_invalid)
support.expect_equal('select invalid numeric input is shown', vim.api.nvim_buf_get_lines(0, 0, 1, false), { ' Input: 9' })
support.feed('<BS>')
support.feed('jj')
support.expect_true('select jj keeps popup open', vim.api.nvim_buf_is_valid(popup_buf))
support.expect_equal('select jj does not choose item', { choice_item, choice_index }, { nil, nil })
support.feed('q')
support.expect_equal('select q aborts', { choice_item, choice_index }, { nil, nil })

open_select()
support.feed('<Esc><Esc>')
support.expect_equal('select double esc aborts', { choice_item, choice_index }, { nil, nil })

support.flush()
