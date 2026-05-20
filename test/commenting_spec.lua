local results = {}

local function expect(name, actual, expected)
  if not vim.deep_equal(actual, expected) then
    error(string.format('%s failed\nexpected: %s\nactual:   %s', name, vim.inspect(expected), vim.inspect(actual)))
  end

  table.insert(results, 'PASS ' .. name)
end

local function reset(lines, filetype, lang)
  vim.cmd('enew!')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.cmd('setlocal buftype=')
  vim.cmd('setlocal bufhidden=wipe')
  vim.cmd('setlocal noswapfile')
  vim.cmd('setfiletype ' .. filetype)

  if lang then
    local ok, parser = pcall(vim.treesitter.get_parser, 0, lang)
    if ok then
      parser:parse(true)
    else
      pcall(vim.treesitter.start, 0, lang)
      local started, started_parser = pcall(vim.treesitter.get_parser, 0, lang)
      if started then
        started_parser:parse(true)
      end
    end
  end

  vim.wait(50)
end

local function feed(keys)
  local termcodes = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(termcodes, 'xt', false)
  vim.wait(50)
end

local function current_lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function assert_default_register(name, expected)
  expect(name, vim.fn.getreg('"'), expected)
end

-- 1. C current-line comments should use // and toggle cleanly.
reset({ 'value;' }, 'c', 'c')
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed('<C-_>')
expect('c current line comment uses //', vim.api.nvim_get_current_line(), '// value;')
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed('<C-_>')
expect('c current line uncomment', vim.api.nvim_get_current_line(), 'value;')

-- 2. Charwise visual comments in C should still use block comments on first press.
reset({ 'value;' }, 'c', 'c')
feed('0v4l<C-_>')
expect('c charwise visual first press uses block comment', vim.api.nvim_get_current_line(), '/* value */;')

-- 3. Visual block comments should react on first press and comment full lines linewise.
reset({ 'alpha', 'beta', 'gamma' }, 'c', 'c')
feed('0<C-v>j<C-_>')
expect('visual block first press comments full lines', current_lines(), {
  '// alpha',
  '// beta',
  'gamma',
})

-- 4. A later charwise visual selection must not inherit prior visual-block behavior.
reset({ 'token;' }, 'c', 'c')
feed('0v4l<C-_>')
expect('charwise visual after block still uses block comment', vim.api.nvim_get_current_line(), '/* token */;')

-- 5. Linewise visual comments should also react on first press.
reset({ 'line one', 'line two', 'line three' }, 'python', 'python')
feed('Vj<C-_>')
expect('linewise visual first press comments selection', current_lines(), {
  '# line one',
  '# line two',
  'line three',
})

-- 6. HTML embedded script comments should prefer the script-language textobject, not outer HTML comments.
reset({
  '<html>',
  '<body>',
  '<!-- outer html comment -->',
  '<script>',
  '// script comment',
  'const value = 1;',
  '</script>',
  '</body>',
  '</html>',
}, 'html', 'html')
vim.api.nvim_win_set_cursor(0, { 5, 4 })
vim.fn.setreg('"', '')
feed('yac')
assert_default_register('html script yac selects script comment', '// script comment\n')
vim.fn.setreg('"', '')
feed('yic')
assert_default_register('html script yic selects inner script comment', 'script comment')

-- 7. C block comments should support inner comment textobjects.
reset({
  '// previous line comment',
  'int value = 0; /* block payload */',
}, 'c', 'c')
vim.api.nvim_win_set_cursor(0, { 2, 22 })
vim.fn.setreg('"', '')
feed('yic')
assert_default_register('c block comment yic selects inner block content', 'block payload')
vim.fn.setreg('"', '')
feed('yac')
assert_default_register('c block comment yac selects full block comment', '/* block payload */')

for _, result in ipairs(results) do
  print(result)
end
