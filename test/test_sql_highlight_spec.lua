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

local function exit_visual_mode()
  if vim.api.nvim_get_mode().mode:find("[vV\22]") then
    vim.cmd("normal! \27")
  end
end

--- Move cursor (1-indexed row, 0-indexed col), call select_corresponding(), return selected text.
local function select_at(row, col)
  exit_visual_mode()
  vim.api.nvim_win_set_cursor(0, { row, col })
  local ok = sql_hl.select_corresponding()
  if not ok then
    exit_visual_mode()
    return nil
  end

  local vpos = vim.fn.getpos("v")
  local cur = vim.api.nvim_win_get_cursor(0)
  local sr, sc = vpos[2] - 1, vpos[3] - 1
  local er, ec = cur[1] - 1, cur[2]
  if sr > er or (sr == er and sc > ec) then
    sr, sc, er, ec = er, ec, sr, sc
  end

  local lines = vim.api.nvim_buf_get_lines(0, sr, er + 1, false)
  exit_visual_mode()
  if #lines == 0 then return nil end
  if #lines == 1 then
    return string.sub(lines[1], sc + 1, ec + 1)
  end

  local parts = { string.sub(lines[1], sc + 1) }
  for i = 2, #lines - 1 do
    table.insert(parts, lines[i])
  end
  table.insert(parts, string.sub(lines[#lines], 1, ec + 1))
  return table.concat(parts, "\n")
end

local function assert_select(test_name, row, col, expected_text)
  local got = select_at(row, col)
  if got == expected_text then
    pass_count = pass_count + 1
    table.insert(results, string.format("  PASS  %s", test_name))
  else
    fail_count = fail_count + 1
    table.insert(results, string.format("  FAIL  %s  (expected %s, got %s)",
      test_name,
      expected_text and string.format("%q", expected_text) or "nil",
      got and string.format("%q", got) or "nil"))
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

-- ── Test 5: Multiple consecutive ping-pong jumps ──────────────────────────
print("--- Test 5: Multiple consecutive ping-pong jumps ---")

do
  local bufnr = open_sql_buf({ "insert into test (name, id) values ('hello', 2);" })
  sql_hl.setup()
  vim.cmd("doautocmd FileType sql")

  -- Move cursor to "name" (col 18)
  vim.api.nvim_win_set_cursor(0, { 1, 18 })

  local all_ok = true
  for step = 1, 10 do
    local ok = sql_hl.select_corresponding()
    if not ok then
      all_ok = false
      fail_count = fail_count + 1
      table.insert(results, string.format("  FAIL  Consecutive jump failed at step %d", step))
      break
    end

    local cur = vim.api.nvim_win_get_cursor(0)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)
    local v_start = vim.fn.getpos("v")[3] - 1
    local v_end = cur[2]
    local sc = math.min(v_start, v_end)
    local ec = math.max(v_start, v_end) + 1
    local text = string.sub(lines[1], sc + 1, ec)
    local expected = (step % 2 == 1) and "'hello'" or "name"

    if text ~= expected then
      all_ok = false
      fail_count = fail_count + 1
      table.insert(results, string.format("  FAIL  Consecutive jump step %d expected %s, got %s", step, expected, text))
      break
    end
  end

  if all_ok then
    pass_count = pass_count + 1
    table.insert(results, "  PASS  10 consecutive ping-pong jumps back and forth between 'name' and ''hello''")
  end
  exit_visual_mode()
end

-- ── Test 6: Cursor on space after comma (', 1' bug reproduction) ────────
print("--- Test 6: Cursor on space after comma ---")

do
  local line = "insert into orders (order_id, user_id, amount, status) values (100, 1, 99.99, 'pending');"
  open_sql_buf({ line })

  assert_highlight("orders: cursor on space in ', 1' -> highlight 'user_id'",
    highlight_at(1, 67), "user_id")
  assert_select("orders: select on space in ', 1' -> select 'user_id'",
    1, 67, "user_id")

  assert_highlight("orders: cursor on space in ', 99.99' -> highlight 'amount'",
    highlight_at(1, 70), "amount")
  assert_select("orders: select on space in ', 99.99' -> select 'amount'",
    1, 70, "amount")

  assert_highlight("orders: cursor on space in ', user_id' -> highlight '1'",
    highlight_at(1, 29), "1")
  assert_select("orders: select on space in ', user_id' -> select '1'",
    1, 29, "1")

  assert_highlight("orders: cursor on ')' -> highlight 'status'",
    highlight_at(1, 87), "status")
end

do
  local line = "insert into test (name, id) values ('hello', 1);"
  open_sql_buf({ line })
  local pos = assert(line:find(", 1", 1, true))

  assert_highlight("simple: cursor on space in ', 1' -> highlight 'id'",
    highlight_at(1, pos), "id")
  assert_select("simple: select on space in ', 1' -> select 'id'",
    1, pos, "id")
end

-- ── Test 7: Spaces before/after commas and multiple spaces ───────────────
print("--- Test 7: Spaces before/after commas ---")

do
  local line = "insert into test ( name , id ) values ( 'hello' ,   1 );"
  open_sql_buf({ line })

  local open_pos = assert(line:find("( 'hello'", 1, true))
  assert_highlight("space after '(' before 'hello' -> highlight 'name'",
    highlight_at(1, open_pos), "name")

  local comma_block = assert(line:find(" ,   1", 1, true))
  assert_highlight("space after 'hello' before ',' -> highlight 'name'",
    highlight_at(1, comma_block - 1), "name")
  assert_highlight("on ',' after 'hello' -> highlight 'name'",
    highlight_at(1, comma_block), "name")
  assert_highlight("first space after ',' before '1' -> highlight 'id'",
    highlight_at(1, comma_block + 1), "id")
  assert_highlight("last space after ',' before '1' -> highlight 'id'",
    highlight_at(1, comma_block + 3), "id")

  local close_block = assert(line:find("1 );", 1, true))
  assert_highlight("space after '1' before ')' -> highlight 'id'",
    highlight_at(1, close_block), "id")
end

-- ── Test 8: Multiline indentation and trailing space after comma ─────────
print("--- Test 8: Multiline indentation and trailing space ---")

do
  local lines = {
    "insert into products (",
    "  sku,",
    "  title,",
    "  price",
    ") values (",
    "  'A001', ",
    "  'Widget',",
    "  19.99",
    ");",
  }
  open_sql_buf(lines)

  assert_highlight("multiline: leading space before 'A001' -> highlight 'sku'",
    highlight_at(6, 0), "sku")
  assert_highlight("multiline: trailing space after comma on row 6 -> highlight 'title'",
    highlight_at(6, #lines[6] - 1), "title")
  assert_highlight("multiline: leading space before 'Widget' -> highlight 'title'",
    highlight_at(7, 0), "title")
  assert_highlight("multiline: leading space before '19.99' -> highlight 'price'",
    highlight_at(8, 0), "price")
  assert_highlight("multiline: cursor on ')' -> highlight 'price'",
    highlight_at(9, 0), "price")
end

-- ── Test 9: Nested expressions containing commas ─────────────────────────
print("--- Test 9: Nested expressions containing commas ---")

do
  local line = "insert into test (name, id, age) values (concat('a', 'b'), coalesce(null, 1), 30);"
  open_sql_buf({ line })

  local b_pos = assert(line:find("'b'", 1, true))
  assert_highlight("nested: cursor on 'b' in concat -> highlight 'name'",
    highlight_at(1, b_pos), "name")

  local coal_comma_sp = assert(line:find(", coalesce", 1, true))
  assert_highlight("nested: cursor on space before coalesce -> highlight 'id'",
    highlight_at(1, coal_comma_sp), "id")

  local one_pos = assert(line:find(", 1)", 1, true)) + 1
  assert_highlight("nested: cursor on '1' in coalesce -> highlight 'id'",
    highlight_at(1, one_pos), "id")

  local age_comma_sp = assert(line:find(", 30", 1, true))
  assert_highlight("nested: cursor on space in ', 30' -> highlight 'age'",
    highlight_at(1, age_comma_sp), "age")
end

-- ── Test 10: Comments inside SQL lists ───────────────────────────────────
print("--- Test 10: Comments inside SQL lists ---")

do
  local line = "insert into test (name, id) values ('hello', /* comment */ 1);"
  open_sql_buf({ line })

  local one_pos = assert(line:find("1);", 1, true)) - 1
  assert_highlight("comments: cursor on '1' -> highlight 'id'",
    highlight_at(1, one_pos), "id")

  local id_pos = assert(line:find("id)", 1, true)) - 1
  assert_highlight("comments: cursor on 'id' -> highlight '1'",
    highlight_at(1, id_pos), "1")

  local sp_pos = assert(line:find(", /*", 1, true))
  assert_highlight("comments: cursor on space right after ',' -> highlight 'id'",
    highlight_at(1, sp_pos), "id")
end

-- ── Test 11: Incomplete / trailing comma and empty middle slot ───────────
print("--- Test 11: Incomplete trailing comma and empty middle slot ---")

do
  local line = "insert into test (name, id) values ('hello', );"
  open_sql_buf({ line })
  local sp_pos = assert(line:find(", )", 1, true))
  assert_highlight("trailing comma: cursor on space after ',' -> highlight 'id'",
    highlight_at(1, sp_pos), "id")
end

do
  local line = "insert into test (name, id, age) values ('hello', , 30);"
  open_sql_buf({ line })

  local mid_sp_pos = assert(line:find(", , 30", 1, true))
  assert_highlight("empty middle slot: cursor on space between commas -> highlight 'id'",
    highlight_at(1, mid_sp_pos), "id")

  local thirty_pos = assert(line:find("30);", 1, true)) - 1
  assert_highlight("empty middle slot: cursor on '30' -> highlight 'age'",
    highlight_at(1, thirty_pos), "age")

  local age_pos = assert(line:find("age)", 1, true)) - 1
  assert_highlight("empty middle slot: cursor on 'age' -> highlight '30'",
    highlight_at(1, age_pos), "30")

  local id_pos = assert(line:find("id,", 1, true)) - 1
  assert_no_highlight("empty middle slot: cursor on 'id' -> no highlight",
    highlight_at(1, id_pos))
end

-- ── Test 12: UTF-8 multi-byte string before ', 1' ────────────────────────
print("--- Test 12: UTF-8 multi-byte string ---")

do
  local line = "insert into test (name, id) values ('你好', 1);"
  open_sql_buf({ line })
  local pos = assert(line:find(", 1", 1, true))

  assert_highlight("utf8: cursor on space in ', 1' -> highlight 'id'",
    highlight_at(1, pos), "id")
  assert_select("utf8: select on space in ', 1' -> select 'id'",
    1, pos, "id")
end

-- ── Test 13: Multi-row INSERT and no-column-list INSERT ──────────────────
print("--- Test 13: Multi-row and no-column-list INSERT ---")

do
  local line = "insert into test (name, id) values ('a', 1), ('b', 2);"
  open_sql_buf({ line })

  local b_pos = assert(line:find("'b'", 1, true)) - 1
  assert_highlight("multi-row: cursor on 'b' -> highlight 'name'",
    highlight_at(1, b_pos), "name")

  local sp2_pos = assert(line:find(", 2", 1, true))
  assert_highlight("multi-row: cursor on space in ', 2' -> highlight 'id'",
    highlight_at(1, sp2_pos), "id")

  local name_pos = assert(line:find("name,", 1, true)) - 1
  assert_highlight("multi-row: cursor on 'name' -> highlight 'a'",
    highlight_at(1, name_pos), "'a'")
end

do
  local line = "insert into test values ('a', 1), ('b', 2);"
  open_sql_buf({ line })

  local a_pos = assert(line:find("'a'", 1, true)) - 1
  assert_no_highlight("no-column-list: cursor on 'a' -> no highlight",
    highlight_at(1, a_pos))

  local b_pos = assert(line:find("'b'", 1, true)) - 1
  assert_no_highlight("no-column-list: cursor on 'b' -> no highlight",
    highlight_at(1, b_pos))
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
