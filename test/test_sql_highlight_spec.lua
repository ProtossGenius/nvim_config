-- test/test_sql_highlight_spec.lua
-- Automated test for sql_highlight.lua INSERT INTO field/value correspondence.
--
-- Usage:
--   nvim -u /home/fakename/.config/nvim/init.lua --headless \
--     -c 'luafile /home/fakename/.config/nvim/test/test_sql_highlight_spec.lua' \
--     -c 'quit'

local ns_name = "sql_insert_highlight"
local ns = vim.api.nvim_create_namespace(ns_name)
local sql_hl = require("user.sql_highlight")

local pass_count = 0
local fail_count = 0
local results = {}

-- ── helpers ──────────────────────────────────────────────────────────────

--- Open a buffer with the given lines, set filetype to sql, parse tree-sitter.
---@param lines string[]
---@return number bufnr
local function open_sql_buf(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = "sql"
  return bufnr
end

--- Move cursor (1-indexed row, 0-indexed col), call highlight, return extmarks.
local function highlight_at(row, col)
  vim.api.nvim_win_set_cursor(0, { row, col })
  sql_hl.highlight_corresponding()
  return vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
end

--- Get the text covered by the first extmark in the current buffer.
---@param marks table  extmark list from nvim_buf_get_extmarks
---@return string|nil
local function extmark_text(marks)
  if #marks == 0 then return nil end
  local m = marks[1]
  local sr, sc = m[2], m[3]
  local details = m[4]
  local er, ec = details.end_row, details.end_col
  local lines = vim.api.nvim_buf_get_lines(0, sr, er + 1, false)
  if #lines == 0 then return nil end
  if #lines == 1 then
    return string.sub(lines[1], sc + 1, ec)
  end
  -- multi-line: first line from sc, middle lines full, last line to ec
  local parts = { string.sub(lines[1], sc + 1) }
  for i = 2, #lines - 1 do
    table.insert(parts, lines[i])
  end
  table.insert(parts, string.sub(lines[#lines], 1, ec))
  return table.concat(parts, "\n")
end

local function assert_highlight(test_name, marks, expected_text)
  local got = extmark_text(marks)
  if got == expected_text then
    pass_count = pass_count + 1
    table.insert(results, string.format("  PASS  %s", test_name))
  else
    fail_count = fail_count + 1
    table.insert(results, string.format("  FAIL  %s  (expected %q, got %s)",
      test_name, expected_text, got and string.format("%q", got) or "nil"))
  end
end

local function assert_no_highlight(test_name, marks)
  if #marks == 0 then
    pass_count = pass_count + 1
    table.insert(results, string.format("  PASS  %s", test_name))
  else
    fail_count = fail_count + 1
    local got = extmark_text(marks)
    table.insert(results, string.format("  FAIL  %s  (expected no highlight, got %s)",
      test_name, got and string.format("%q", got) or "extmarks present"))
  end
end

-- ── Test 1: single-line INSERT ──────────────────────────────────────────
-- insert into users (id, name, age) values (1, 'alice', 30);
  -- TS ranges: id=[19,21] name=[23,27] age=[29,32] | 1=[42,43] 'alice'=[45,52] 30=[54,56]
print("\n=== SQL Insert Highlight Tests ===\n")
print("--- Test 1: single-line INSERT INTO ---")

do
  open_sql_buf({ "insert into users (id, name, age) values (1, 'alice', 30);" })

  -- cursor on "id" (col 19) → should highlight value "1"
  assert_highlight("cursor on 'id' → highlight '1'",
    highlight_at(1, 19), "1")

  -- cursor on "name" (col 23) → should highlight value "'alice'"
  assert_highlight("cursor on 'name' → highlight 'alice'",
    highlight_at(1, 23), "'alice'")

  -- cursor on "age" (col 29) → should highlight value "30"
  assert_highlight("cursor on 'age' → highlight '30'",
    highlight_at(1, 29), "30")

  -- Reverse: cursor on value "1" (col 42, inside literal) → should highlight field "id"
  assert_highlight("cursor on '1' → highlight 'id'",
    highlight_at(1, 42), "id")

  -- cursor on value "'alice'" (col 45) → should highlight field "name"
  assert_highlight("cursor on 'alice' → highlight 'name'",
    highlight_at(1, 45), "name")

  -- cursor on value "30" (col 54, inside literal) → should highlight field "age"
  assert_highlight("cursor on '30' → highlight 'age'",
    highlight_at(1, 54), "age")

  -- cursor on "insert" keyword → should NOT highlight anything
  assert_no_highlight("cursor on 'insert' keyword → no highlight",
    highlight_at(1, 0))

  -- cursor on table name "users" → should NOT highlight anything
  assert_no_highlight("cursor on 'users' → no highlight",
    highlight_at(1, 12))
end

-- ── Test 2: longer single-line INSERT ───────────────────────────────────
print("--- Test 2: 4-column INSERT INTO ---")

do
  open_sql_buf({ "insert into orders (order_id, user_id, amount, status) values (100, 1, 99.99, 'pending');" })

  -- TS ranges: order_id=[20,28] user_id=[30,37] amount=[39,45] status=[47,53]
  --            100=[63,66] 1=[68,69] 99.99=[71,76] 'pending'=[78,87]

  -- cursor on "order_id" → highlight "100"
  assert_highlight("cursor on 'order_id' → highlight '100'",
    highlight_at(1, 20), "100")

  -- cursor on "status" → highlight "'pending'"
  assert_highlight("cursor on 'status' → highlight 'pending'",
    highlight_at(1, 47), "'pending'")

  -- cursor on "99.99" (col 71, inside literal) → highlight "amount"
  assert_highlight("cursor on '99.99' → highlight 'amount'",
    highlight_at(1, 71), "amount")

  -- cursor on delimiter: '(' before values (col 62) → snap to first value → highlight 'order_id'
  assert_highlight("cursor on '(' before values → highlight 'order_id'",
    highlight_at(1, 62), "order_id")

  -- cursor on ',' between 1 and 99.99 (col 69) → snap to previous value '1' → highlight 'user_id'
  assert_highlight("cursor on ',' after '1' → highlight 'user_id'",
    highlight_at(1, 69), "user_id")
end

-- ── Test 3: multi-line INSERT ───────────────────────────────────────────
print("--- Test 3: multi-line INSERT INTO ---")

do
  open_sql_buf({
    "insert into",
    "  products",
    "  (sku, title, price)",
    "values",
    "  ('A001', 'Widget', 19.99);",
  })

  -- cursor on "sku" (row 3, col ~3) → highlight "'A001'"
  assert_highlight("multiline: cursor on 'sku' → highlight 'A001'",
    highlight_at(3, 3), "'A001'")

  -- cursor on "title" (row 3) → highlight "'Widget'"
  assert_highlight("multiline: cursor on 'title' → highlight 'Widget'",
    highlight_at(3, 8), "'Widget'")

  -- cursor on "price" (row 3) → highlight "19.99"
  assert_highlight("multiline: cursor on 'price' → highlight '19.99'",
    highlight_at(3, 15), "19.99")

  -- Reverse: cursor on "'A001'" (row 5) → highlight "sku"
  assert_highlight("multiline: cursor on 'A001' → highlight 'sku'",
    highlight_at(5, 3), "sku")
end

-- ── Test 4: user's exact scenario ───────────────────────────────────────
-- Reproduces: insert into test (name, id) values ('hello', 2);
print("--- Test 4: user's exact scenario (mine.sql) ---")

do
  open_sql_buf({ "insert into test (name, id) values ('hello', 2);" })

  -- cursor on "name" → should highlight "'hello'"
  assert_highlight("mine.sql: cursor on 'name' → highlight 'hello'",
    highlight_at(1, 18), "'hello'")

  -- cursor on "id" → should highlight "2"
  assert_highlight("mine.sql: cursor on 'id' → highlight '2'",
    highlight_at(1, 24), "2")

  -- Reverse: cursor on "'hello'" → should highlight "name"
  assert_highlight("mine.sql: cursor on 'hello' → highlight 'name'",
    highlight_at(1, 37), "name")

  -- Reverse: cursor on "2" → should highlight "id"
  assert_highlight("mine.sql: cursor on '2' → highlight 'id'",
    highlight_at(1, 45), "id")
end

-- ── Test 5: '=' shortcut jump and select ──────────────────────────────────
print("--- Test 5: '=' shortcut jump and select ---")

do
  local bufnr = open_sql_buf({ "insert into test (name, id) values ('hello', 2);" })
  sql_hl.setup()
  vim.cmd("doautocmd FileType sql")

  -- Move cursor to "name" (col 18)
  vim.api.nvim_win_set_cursor(0, { 1, 18 })

  local sr, sc, er, ec = sql_hl.get_corresponding_range(bufnr)
  if sr then
    local start_row = sr + 1
    local start_col = sc
    local end_row = er + 1
    local end_col = math.max(sc, ec - 1)

    vim.api.nvim_win_set_cursor(0, { start_row, start_col })
    vim.cmd("normal! v")
    vim.api.nvim_win_set_cursor(0, { end_row, end_col })
  end

  local mode = vim.api.nvim_get_mode().mode
  local lines_sel = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)
  local sel_text = string.sub(lines_sel[1], sc + 1, ec)
  vim.cmd("normal! \27") -- Exit visual mode

  if mode == "v" and sel_text == "'hello'" then
    pass_count = pass_count + 1
    table.insert(results, "  PASS  '=' shortcut from 'name' selected ''hello'' in visual mode")
  else
    fail_count = fail_count + 1
    table.insert(results, string.format("  FAIL  '=' shortcut from 'name' failed (mode=%s, text=%s)", mode, sel_text))
  end
end

-- ── Summary ─────────────────────────────────────────────────────────────
print("")
for _, r in ipairs(results) do
  print(r)
end
print(string.format("\n=== Results: %d passed, %d failed ===\n",
  pass_count, fail_count))

if fail_count > 0 then
  vim.cmd("cquit 1")
end
