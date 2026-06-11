local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

package.loaded['user.telescope_path'] = nil
local telescope_path = require('user.telescope_path')

local original_is_valid = vim.api.nvim_win_is_valid
local original_get_width = vim.api.nvim_win_get_width

local mock_width = 80
vim.api.nvim_win_is_valid = function(win)
  return true
end
vim.api.nvim_win_get_width = function(win)
  return mock_width
end

local function run_test(path, query, width, expected)
  mock_width = width
  local opts = {
    picker = {
      results_win = 1,
      _get_prompt = function() return query end
    }
  }
  local actual = telescope_path.get_shortened_path(path, opts)
  support.expect_equal(
    string.format("path: %s, query: %q, width: %d", path, query, width),
    actual,
    expected
  )
end

-- Test cases
-- 1. Full path fits under max_len (width 80 -> max_len 65)
run_test(
  "src/main/java/com/example/App.java",
  "",
  80,
  "src/main/java/com/example/App.java"
)

-- 2. Path too long, query is empty, keep filename intact and abbreviate directory (width 80 -> max_len 65)
run_test(
  "some/very/long/path/to/a/deep/package/structure/for/my/project/SomeClass.java",
  "",
  80,
  "*/path/to/a/deep/package/structure/for/my/project/SomeClass.java"
)

-- 3. Path too long, query is empty, narrow width (width 35 -> max_len 20)
run_test(
  "some/very/long/path/to/a/deep/package/structure/for/my/project/SomeClass.java",
  "",
  35,
  "*/SomeClass.java"
)

-- 4. Path too long, query is empty, extremely narrow width with very long filename (width 40 -> max_len 25)
run_test(
  "some/very/long/path/to/a/deep/package/structure/for/my/project/SuperLongClassNameThatGoesOnAndOn.java",
  "",
  40,
  "*/ThatGoesOnAndOn.java"
)

-- 5. Non-empty query, verify it matches fuzzy-search behavior
run_test(
  "some/very/long/path/to/a/deep/package/structure/for/my/project/SomeClass.java",
  "SomeClass",
  45, -- max_len = 30
  "*/my/project/SomeClass.java"
)

-- Restore original functions
vim.api.nvim_win_is_valid = original_is_valid
vim.api.nvim_win_get_width = original_get_width

support.flush()
