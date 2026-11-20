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

local function exit_visual_mode()
  if vim.api.nvim_get_mode().mode:find('[vV\22]') then
    vim.cmd('normal! \27')
  end
end

local function read_visual_text()
  local vpos = vim.fn.getpos('v')
  local cur = vim.api.nvim_win_get_cursor(0)
  local sr, sc = vpos[2] - 1, vpos[3] - 1
  local er, ec = cur[1] - 1, cur[2]
  if sr > er or (sr == er and sc > ec) then
    sr, sc, er, ec = er, ec, sr, sc
  end

  local lines = vim.api.nvim_buf_get_lines(0, sr, er + 1, false)
  exit_visual_mode()
  if #lines == 0 then
    return nil
  end

  local last_line = lines[#lines]
  local end_inclusive = ec + 1 + vim.str_utf_end(last_line, ec + 1)
  if #lines == 1 then
    return string.sub(last_line, sc + 1, end_inclusive)
  end

  local parts = { string.sub(lines[1], sc + 1) }
  for i = 2, #lines - 1 do
    table.insert(parts, lines[i])
  end
  table.insert(parts, string.sub(last_line, 1, end_inclusive))
  return table.concat(parts, '\n')
end

local function range_text(sr, sc, er, ec)
  if not sr then
    return nil
  end
  return table.concat(vim.api.nvim_buf_get_text(0, sr, sc, er, ec, {}), '\n')
end

local function expect_range_text(name, lines, filetype, lang, row, col, expected_text)
  exit_visual_mode()
  support.reset(lines, filetype, lang)
  vim.api.nvim_win_set_cursor(0, { row, col })
  local actual = range_text(printf_highlight.get_corresponding_range(0))
  support.expect_equal(name, actual, expected_text)
end

local function expect_select(name, lines, filetype, lang, row, col, expected_text)
  exit_visual_mode()
  support.reset(lines, filetype, lang)
  vim.api.nvim_win_set_cursor(0, { row, col })
  local ok = printf_highlight.select_corresponding()
  local actual = ok and read_visual_text() or nil
  exit_visual_mode()
  support.expect_equal(name, actual, expected_text)
end

local function expect_ping_pong(name, lines, filetype, lang, start_row, start_col, expected_sequence)
  exit_visual_mode()
  support.reset(lines, filetype, lang)
  vim.api.nvim_win_set_cursor(0, { start_row, start_col })
  local actual = {}
  for _ = 1, #expected_sequence do
    local ok = printf_highlight.select_corresponding()
    if not ok then
      table.insert(actual, false)
      break
    end
    local vpos = vim.fn.getpos('v')
    local cur = vim.api.nvim_win_get_cursor(0)
    local sr, sc = vpos[2] - 1, vpos[3] - 1
    local er, ec = cur[1] - 1, cur[2]
    if sr > er or (sr == er and sc > ec) then
      sr, sc, er, ec = er, ec, sr, sc
    end
    local sel_lines = vim.api.nvim_buf_get_lines(0, sr, er + 1, false)
    local last_line = sel_lines[#sel_lines]
    local end_inclusive = ec + 1 + vim.str_utf_end(last_line, ec + 1)
    if #sel_lines == 1 then
      table.insert(actual, string.sub(last_line, sc + 1, end_inclusive))
    else
      local parts = { string.sub(sel_lines[1], sc + 1) }
      for i = 2, #sel_lines - 1 do
        table.insert(parts, sel_lines[i])
      end
      table.insert(parts, string.sub(last_line, 1, end_inclusive))
      table.insert(actual, table.concat(parts, '\n'))
    end
  end
  exit_visual_mode()
  support.expect_equal(name, actual, expected_sequence)
end

-- 1. Nested function/method call arguments & ping-pong
do
  local line = 'log.info("a={} b={}", user.getName(), items.size());'
  local col = support.find_substring(line, 'user.getName()') - 1
  expect_ping_pong('java nested method call ping-pong', { line }, 'java', 'java', 1, col, {
    '{}',
    'user.getName()',
    '{}',
    'user.getName()',
  })
end

do
  local line = 'printf("%s %d", get_name(x), get_count());'
  local col = support.find_substring(line, 'get_name(x)') - 1
  expect_ping_pong('c nested func call ping-pong', { line }, 'c', 'c', 1, col, {
    '%s',
    'get_name(x)',
    '%s',
    'get_name(x)',
  })
end

-- 2. Comma & space boundary consistency with SQL
do
  local line = 'printf("%s %d", name, count);'
  local fmt_comma_col = support.find_substring(line, '",')
  expect_range_text('comma after format string -> nil', { line }, 'c', 'c', 1, fmt_comma_col, nil)
  expect_range_text('space after format comma -> %s', { line }, 'c', 'c', 1, fmt_comma_col + 1, '%s')

  local name_comma_col = support.find_substring(line, ', count') - 1
  expect_range_text('comma after name -> %s', { line }, 'c', 'c', 1, name_comma_col, '%s')
  expect_range_text('space in ", count" -> %d', { line }, 'c', 'c', 1, name_comma_col + 1, '%d')
end

do
  local lines = {
    'printf(',
    '  "%s %d",',
    '  name,',
    '  count',
    ');',
  }
  local comma_col = support.find_substring(lines[3], ',') - 1
  expect_range_text('multiline comma after name -> %s', lines, 'c', 'c', 3, comma_col, '%s')
  expect_range_text('multiline indent before count -> %d', lines, 'c', 'c', 4, 0, '%d')
end

-- 3. Nested containers with inner commas across languages
do
  local line = 'println!("{} {}", foo(1, 2), c);'
  local col = support.find_substring(line, ', c') + 1
  expect_range_text('rust foo(1, 2) ignores inner comma', { line }, 'rust', 'rust', 1, col, '{}')
end

do
  local line = 'println!("{} {}", a + b, -1);'
  local first_col = support.find_substring(line, '{}', 1) - 1
  local second_col = support.find_substring(line, '{}', 2) - 1
  expect_ping_pong('rust a + b ping-pong', { line }, 'rust', 'rust', 1, first_col, {
    'a + b',
    '{}',
    'a + b',
  })
  expect_ping_pong('rust -1 ping-pong', { line }, 'rust', 'rust', 1, second_col, {
    '-1',
    '{}',
    '-1',
  })
end

do
  local line = 'log.info("{} {}", new int[]{1, 2}, 3);'
  expect_range_text('java array initializer inner comma', { line }, 'java', 'java', 1, #line - 3, '{}')
end

do
  local line = 'log.info("{} {}", new HashMap<String, Integer>(), 3);'
  expect_range_text('java generic type_arguments inner comma', { line }, 'java', 'java', 1, #line - 3, '{}')
end

do
  local line = 'printf("%d %d", std::pair<int, int>{1, 2}.first, 3);'
  expect_range_text('cpp template + init list inner commas', { line }, 'cpp', 'cpp', 1, #line - 3, '%d')
end

do
  local line = 'fmt.Printf("%v %d", []int{1, 2}, 3)'
  expect_range_text('go slice literal inner comma', { line }, 'go', 'go', 1, #line - 2, '%d')
end

do
  local line = 'logger.info("%s %d", [1, 2], 3)'
  expect_range_text('python list arg inner comma', { line }, 'python', 'python', 1, #line - 2, '%d')
  local line_tuple = 'logger.info("%s %d", (1, 2), 3)'
  expect_range_text('python tuple arg inner comma', { line_tuple }, 'python', 'python', 1, #line_tuple - 2, '%d')
  local line_dict = 'logger.info("%s %d", {"a": 1, "b": 2}, 3)'
  expect_range_text('python dict arg inner comma', { line_dict }, 'python', 'python', 1, #line_dict - 2, '%d')
end

do
  local line = 'string.format("%s %d", {1, 2}, 3)'
  expect_range_text('lua table arg inner comma', { line }, 'lua', 'lua', 1, #line - 2, '%d')
end

do
  local line_arr = 'console.log("%s %d", [1, 2], 3);'
  expect_range_text('ts array arg inner comma', { line_arr }, 'typescript', 'typescript', 1, #line_arr - 3, '%d')
  local line_obj = 'console.log("%s %d", {a: 1, b: 2}, 3);'
  expect_range_text('ts object arg inner comma', { line_obj }, 'typescript', 'typescript', 1, #line_obj - 3, '%d')
end

-- 4. Comments in args & empty middle slot
do
  local line = 'printf("%s %d", /* comment */ a, b);'
  local col = support.find_substring(line, '%s') - 1
  expect_select('c comment in args skips comment', { line }, 'c', 'c', 1, col, 'a')
  local col2 = support.find_substring(line, '%d') - 1
  expect_select('c comment in args 2nd placeholder -> b', { line }, 'c', 'c', 1, col2, 'b')
end

do
  local line = 'printf("%s %d", , b);'
  local col1 = support.find_substring(line, '%s') - 1
  local col2 = support.find_substring(line, '%d') - 1
  expect_range_text('c empty middle slot 1st -> nil', { line }, 'c', 'c', 1, col1, nil)
  expect_range_text('c empty middle slot 2nd -> b', { line }, 'c', 'c', 1, col2, 'b')
end

-- 5. Multiline argument with end_col < start_col (no overshoot + ping-pong)
do
  local lines = {
    'printf("%s %d",',
    '       "hello",',
    '       1 +',
    '  2);',
  }
  local col = support.find_substring(lines[1], '%d') - 1
  expect_ping_pong('c multiline smaller end_col ping-pong', lines, 'c', 'c', 1, col, {
    '1 +\n  2',
    '%d',
    '1 +\n  2',
  })
end

-- 6. Live buffer edit without manual parser:parse()
do
  exit_visual_mode()
  support.reset({ 'printf("%s", a);' }, 'c', 'c')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'printf("%s %d", a, b);' })
  local col = support.find_substring('printf("%s %d", a, b);', 'b);') - 1
  vim.api.nvim_win_set_cursor(0, { 1, col })
  printf_highlight.update_highlights(0)
  local got = range_text(printf_highlight.get_corresponding_range(0))
  support.expect_equal('c live edit without manual parse()', got, '%d')
end

-- 7. Java SLF4J edge cases
expect_range_text('java slf4j json', { 'log.info("json={\\"a\\":{}}", x);' }, 'java', 'java', 1, 22, 'x')
expect_range_text('java slf4j {{}}', { 'log.info("{{}}", x);' }, 'java', 'java', 1, 11, 'x')
expect_range_text('java slf4j escaped \\{}', { 'log.info("\\\\{}", x);' }, 'java', 'java', 1, 12, nil)
expect_range_text('java slf4j unescaped \\\\{}', { 'log.info("\\\\\\\\{}", x);' }, 'java', 'java', 1, 14, 'x')
do
  local line = 'log.info("a={} " + "b={}", x, y);'
  local col = support.find_substring(line, '{}', 2) - 1
  expect_ping_pong('java concat format string', { line }, 'java', 'java', 1, col, {
    'y',
    '{}',
    'y',
  })
end

-- 8. Raw / template / long strings, C concatenated + comment, C++ std::format
expect_range_text('go raw string', { 'fmt.Printf(`%s %d`, a, b)' }, 'go', 'go', 1, 23, '%d')
expect_range_text('ts template string', { 'console.log(`%s %d`, a, b);' }, 'typescript', 'typescript', 1, 24, '%d')
expect_range_text('ts template skips ${a % d}', { 'console.log(`x=${a % d} %s`, b);' }, 'typescript', 'typescript', 1, 29, '%s')
expect_range_text('cpp raw string', { 'printf(R"(%s %d)", a, b);' }, 'cpp', 'cpp', 1, 13, 'b')
expect_range_text('rust raw string', { 'println!(r#"{} {}"#, a, b);' }, 'rust', 'rust', 1, 23, '{}')
expect_range_text('lua long string', { 'string.format([[%s %d]], a, b)' }, 'lua', 'lua', 1, 28, '%d')
do
  local line = 'printf("a=%s " /* %d */ "b=%d", x, y);'
  local col = support.find_substring(line, '%d', 2) - 1
  expect_range_text('c concat string skips inline comment %d', { line }, 'c', 'c', 1, col, 'y')
end
expect_range_text('cpp std::format', { 'std::format("{} {}", a, b);' }, 'cpp', 'cpp', 1, 16, 'b')

-- 9. Positional & named placeholders
do
  local line = 'printf("%2$s %1$d", count, name);'
  local col = support.find_substring(line, '%2$s') - 1
  expect_range_text('c positional %2$s -> name', { line }, 'c', 'c', 1, col, 'name')
end
do
  local line = 'println!("{1} {0}", first, second);'
  local col = support.find_substring(line, '{1}') - 1
  expect_range_text('rust positional {1} -> second', { line }, 'rust', 'rust', 1, col, 'second')
end
do
  local line = 'println!("{name} {}", val);'
  local col = support.find_substring(line, '{}') - 1
  expect_range_text('rust named {name} skipped, {} -> val', { line }, 'rust', 'rust', 1, col, 'val')
end
do
  local line = 'String.format("%s%n%d", name, count);'
  local col = support.find_substring(line, '%d') - 1
  expect_range_text('java %n does not consume arg', { line }, 'java', 'java', 1, col, 'count')
end

-- 10. Unclosed ERROR calls while typing
expect_range_text('c unclosed ERROR trailing space', { 'printf("%s %d", a, ' }, 'c', 'c', 1, 18, '%d')
expect_range_text('java unclosed ERROR trailing space', { 'log.info("{} {}", a, ' }, 'java', 'java', 1, 20, '{}')
expect_range_text('python unclosed ERROR trailing space', { 'logger.info("%s %d", a, ' }, 'python', 'python', 1, 23, '%d')

-- 11. Visual mode preserved when select_corresponding() has no match
do
  exit_visual_mode()
  support.reset({ 'int x = 123;' }, 'c', 'c')
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  vim.cmd('normal! vll')
  local ok = printf_highlight.select_corresponding()
  local mode = vim.api.nvim_get_mode().mode
  exit_visual_mode()
  support.expect_equal('visual mode preserved on no-match (returns false)', ok, false)
  support.expect_equal('visual mode preserved on no-match (mode stays v)', mode, 'v')
end

support.flush()
