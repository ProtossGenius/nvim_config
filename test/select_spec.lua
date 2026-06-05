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
support.feed('.')
support.expect_equal('select dot chooses current item', { choice_item, choice_index }, { 'alpha', 1 })

open_select()
popup_buf = vim.api.nvim_get_current_buf()
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

-- Tests for select_many
local selected_choices

local function open_select_many(initial_selected)
  selected_choices = nil
  local opts = {
    is_selected = function(item)
      if initial_selected then
        for _, selected in ipairs(initial_selected) do
          if selected == item then return true end
        end
      end
      return false
    end
  }
  select.select_many({ 'alpha', 'beta', 'gamma' }, 'Test Select Many', nil, opts, function(result)
    selected_choices = result
  end)
  vim.wait(100)
end

-- 1. Test basic rendering and checkbox states
open_select_many({ 'beta' })
support.expect_equal('select_many initial checked state beta', vim.api.nvim_buf_get_lines(0, 1, -1, false), {
  " 1. [ ] alpha",
  " 2. [x] beta",
  " 3. [ ] gamma"
})

-- 2. Test toggling with default key '-'
support.feed('j-') -- Toggle line 3 (beta -> unchecked)
support.expect_equal('select_many toggle unchecked', vim.api.nvim_buf_get_lines(0, 1, -1, false), {
  " 1. [ ] alpha",
  " 2. [ ] beta",
  " 3. [ ] gamma"
})

-- 3. Test toggling with '<Space>'
support.feed('j<Space>') -- Move to line 3 (gamma) and toggle to checked
support.expect_equal('select_many toggle checked space', vim.api.nvim_buf_get_lines(0, 1, -1, false), {
  " 1. [ ] alpha",
  " 2. [ ] beta",
  " 3. [x] gamma"
})

-- 4. Test finish selection with '<CR>'
support.feed('<CR>')
support.expect_equal('select_many returns selected items', selected_choices, { 'gamma' })

-- 5. Test abort with 'q'
open_select_many()
support.feed('q')
support.expect_equal('select_many abort q returns empty table', selected_choices, {})

-- 6. Test custom toggle key configuration
vim.g.select_many_toggle_keys = { "x" }
open_select_many()
support.feed('x') -- Toggle line 1 (alpha)
support.expect_equal('select_many toggle custom key x', vim.api.nvim_buf_get_lines(0, 1, -1, false), {
  " 1. [x] alpha",
  " 2. [ ] beta",
  " 3. [ ] gamma"
})
-- Confirm default key '-' no longer toggles
support.feed('-')
support.expect_equal('select_many default key no longer toggles', vim.api.nvim_buf_get_lines(0, 1, -1, false), {
  " 1. [x] alpha",
  " 2. [ ] beta",
  " 3. [ ] gamma"
})
support.feed('<CR>')
support.expect_equal('select_many returns custom selection', selected_choices, { 'alpha' })

-- Restore default config
vim.g.select_many_toggle_keys = { "-", "<Space>" }

support.flush()

