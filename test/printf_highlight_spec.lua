local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
local printf_highlight = require('user.printf_highlight')

local function sort_highlights(highlights)
  table.sort(highlights, function(left, right)
    if left.row ~= right.row then
      return left.row < right.row
    end
    if left.col ~= right.col then
      return left.col < right.col
    end
    return left.hl_group < right.hl_group
  end)

  return highlights
end

local function assert_pair(name, lines, filetype, lang, placeholder_line, placeholder_text, placeholder_occurrence, arg_line, arg_text)
  support.reset(lines, filetype, lang)
  local placeholder_col = support.find_substring(lines[placeholder_line], placeholder_text, placeholder_occurrence or 1) - 1
  local arg_col = support.find_substring(lines[arg_line], arg_text) - 1
  local expected = sort_highlights({
    {
      row = arg_line - 1,
      col = arg_col,
      end_row = arg_line - 1,
      end_col = arg_col + #arg_text,
      hl_group = 'PrintfArgument',
    },
    {
      row = placeholder_line - 1,
      col = placeholder_col,
      end_row = placeholder_line - 1,
      end_col = placeholder_col + #placeholder_text,
      hl_group = 'PrintfPlaceholder',
    },
  })

  support.set_cursor_on_substring(placeholder_line, placeholder_text, placeholder_occurrence or 1)
  printf_highlight.update_highlights(0)
  support.expect_equal(name .. ' placeholder->arg', support.get_highlights(printf_highlight.ns_id), expected)

  support.set_cursor_on_substring(arg_line, arg_text)
  printf_highlight.update_highlights(0)
  support.expect_equal(name .. ' arg->placeholder', support.get_highlights(printf_highlight.ns_id), expected)
end

assert_pair(
  'c printf',
  { 'printf("%d %s", value, name);' },
  'c',
  'c',
  1,
  '%d',
  1,
  1,
  'value'
)

assert_pair(
  'java slf4j',
  { 'log.info("value {} {}", firstValue, secondValue);' },
  'java',
  'java',
  1,
  '{}',
  2,
  1,
  'secondValue'
)

assert_pair(
  'java string format',
  { 'String.format("%s-%d", name, count);' },
  'java',
  'java',
  1,
  '%d',
  1,
  1,
  'count'
)

assert_pair(
  'lua string.format',
  { 'string.format("%s %d", name, count)' },
  'lua',
  'lua',
  1,
  '%s',
  1,
  1,
  'name'
)

assert_pair(
  'go fmt.Printf',
  { 'fmt.Printf("%d %s", value, label)' },
  'go',
  'go',
  1,
  '%s',
  1,
  1,
  'label'
)

assert_pair(
  'typescript console.log',
  { 'console.log("value %s", item)' },
  'typescript',
  'typescript',
  1,
  '%s',
  1,
  1,
  'item'
)

assert_pair(
  'rust println',
  { 'println!("value {} {:?}", item, detail);' },
  'rust',
  'rust',
  1,
  '{:?}',
  1,
  1,
  'detail'
)

assert_pair(
  'python logger',
  { 'logger.info("value %s %s", first, second)' },
  'python',
  'python',
  1,
  '%s',
  2,
  1,
  'second'
)

support.flush()
