local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
local project = require('user.project')
local luabind = require('user.luabind')
local user_lsp = require('user.lsp')
local jump = require('user.jump')

local config_root = vim.fn.stdpath('config')
local demo_root = vim.fs.joinpath(config_root, 'test-projects/lua-luabind-demo')
local game_lua_path = vim.fs.joinpath(demo_root, 'scripts/game.lua')
local cpp_bindings_path = vim.fs.joinpath(demo_root, '.luabind/battle_bindings.cpp')

-- ── 1. Project root detection ────────────────────────────────────────────────
support.expect_equal(
  'project root detected via .proj',
  project.root(game_lua_path),
  demo_root
)

support.expect_equal(
  'luabind root detected via .proj',
  luabind.get_project_root(game_lua_path),
  demo_root
)

-- ── 2. .luabind directory detection ──────────────────────────────────────────
support.expect_true(
  '.luabind folder detected under demo root',
  luabind.has_luabind(demo_root)
)

local luabind_path, path_type = luabind.get_luabind_path(demo_root)
support.expect_equal(
  'luabind path resolves correctly',
  luabind_path,
  vim.fs.joinpath(demo_root, '.luabind')
)
support.expect_equal(
  'luabind path type is directory',
  path_type,
  'directory'
)

-- ── 3. Parsing C++ methods from .luabind ──────────────────────────────────────
luabind.clear_cache(demo_root)
local methods = luabind.get_methods(demo_root)
support.expect_true('found at least 4 methods', #methods >= 4)

local function find_by_name(name, class_name)
  for _, m in ipairs(methods) do
    if m.name == name and (not class_name or m.class_name == class_name) then
      return m
    end
  end
  return nil
end

-- Test calculate_damage
local calc_method = find_by_name('calculate_damage')
support.expect_true('calculate_damage method parsed', calc_method ~= nil)
support.expect_equal('calculate_damage return type', calc_method.return_type, 'int')
support.expect_equal('calculate_damage params', calc_method.params, 'int attacker_id, int raw_damage')
support.expect_true('calculate_damage has doc comments', #calc_method.doc_comments > 0)
local has_calc_doc = false
for _, c in ipairs(calc_method.doc_comments) do
  if c:find('Calculate damage dealt by an attacker') then has_calc_doc = true end
end
support.expect_true('calculate_damage doc comment content', has_calc_doc)

support.expect_true('calculate_damage has method body comments', #calc_method.body_comments > 0)
local has_calc_body = false
for _, c in ipairs(calc_method.body_comments) do
  if c:find('方法体注释：若触发暴击') then has_calc_body = true end
end
support.expect_true('calculate_damage method body comment content', has_calc_body)
support.expect_equal('calculate_damage file path', calc_method.file, cpp_bindings_path)
support.expect_equal('calculate_damage line number', calc_method.line, 10)

-- Test Player::heal
local heal_method = find_by_name('heal', 'Player')
support.expect_true('Player::heal method parsed', heal_method ~= nil)
support.expect_equal('Player::heal class name', heal_method.class_name, 'Player')
support.expect_true('Player::heal has doc comments', #heal_method.doc_comments > 0)
support.expect_true('Player::heal has method body comments', #heal_method.body_comments > 0)
local has_heal_body = false
for _, c in ipairs(heal_method.body_comments) do
  if c:find('方法体注释：增加血量') then has_heal_body = true end
end
support.expect_true('Player::heal method body comment content', has_heal_body)
support.expect_equal('Player::heal line number', heal_method.line, 28)

-- Test Player::teleport (merged doc comments + body comments)
local teleport_method = find_by_name('teleport', 'Player')
support.expect_true('Player::teleport method parsed', teleport_method ~= nil)
support.expect_true('Player::teleport has doc comments', #teleport_method.doc_comments > 0)
support.expect_true('Player::teleport has body comments', #teleport_method.body_comments > 0)
local has_tp_body = false
for _, c in ipairs(teleport_method.body_comments) do
  if c:find('方法体注释：瞬移到指定目标点') then has_tp_body = true end
end
support.expect_true('Player::teleport method body comment content', has_tp_body)

-- Test set_speed from character.luabind
local speed_method = find_by_name('set_speed')
support.expect_true('set_speed method parsed from character.luabind', speed_method ~= nil)
support.expect_true('set_speed has doc comment', #speed_method.doc_comments > 0)

-- ── 4. Formatted documentation (Hover / Completion) ──────────────────────────
local doc_text = luabind.format_documentation(calc_method)
support.expect_true('doc contains C++ signature', doc_text:find('int calculate_damage%(int attacker_id, int raw_damage%)') ~= nil)
support.expect_true('doc contains Documentation section', doc_text:find('### 📖 Documentation') ~= nil)
support.expect_true('doc contains Method Body Comments section', doc_text:find('### 💡 Method Body Comments') ~= nil)
support.expect_true('doc contains exact body comment', doc_text:find('方法体注释：若触发暴击') ~= nil)
support.expect_true('doc contains file reference', doc_text:find('Defined in:') ~= nil)

-- ── 5. nvim-cmp completion items ─────────────────────────────────────────────
vim.cmd('edit ' .. vim.fn.fnameescape(game_lua_path))
local game_buf = vim.api.nvim_get_current_buf()
luabind.attach_to_buffer(game_buf)

local cmp_items = luabind.get_cmp_items()
support.expect_true('cmp items returned', #cmp_items > 0)

local found_calc_cmp = false
for _, item in ipairs(cmp_items) do
  if item.label == 'calculate_damage' then
    found_calc_cmp = true
    support.expect_true('cmp item detail contains C++ luabind', item.detail:find('%[C%+%+ luabind%]') ~= nil)
    support.expect_true('cmp item documentation has body comment', item.documentation.value:find('方法体注释：若触发暴击') ~= nil)
  end
end
support.expect_true('found calculate_damage in cmp items', found_calc_cmp)

-- Completion with class prefix context (e.g. player:)
local class_cmp_items = luabind.get_cmp_items({
  context = {
    cursor_before_line = 'player:he',
  }
})
local found_heal_in_class_cmp = false
for _, item in ipairs(class_cmp_items) do
  if item.label == 'heal' then
    found_heal_in_class_cmp = true
    support.expect_true('heal documentation contains method body comment', item.documentation.value:find('方法体注释：增加血量') ~= nil)
  end
end
support.expect_true('heal item returned for player: prefix', found_heal_in_class_cmp)

-- ── 6. Jump to definition ────────────────────────────────────────────────────
-- Line 3: local dmg = calculate_damage(1, 100)
vim.api.nvim_win_set_cursor(0, { 3, 20 }) -- On calculate_damage
local jumped_calc = luabind.jump_to_definition({ bufnr = game_buf })
support.expect_true('jumped to calculate_damage definition', jumped_calc)
support.expect_equal('jumped buffer is battle_bindings.cpp', vim.api.nvim_buf_get_name(0), cpp_bindings_path)
support.expect_equal('jumped line is 10', vim.api.nvim_win_get_cursor(0)[1], 10)

-- Switch back to game.lua
vim.cmd('edit ' .. vim.fn.fnameescape(game_lua_path))
-- Line 5: player:heal(50)
vim.api.nvim_win_set_cursor(0, { 5, 12 }) -- On heal
local jumped_heal = luabind.jump_to_definition({ bufnr = game_buf })
support.expect_true('jumped to heal definition', jumped_heal)
support.expect_equal('jumped buffer is battle_bindings.cpp', vim.api.nvim_buf_get_name(0), cpp_bindings_path)
support.expect_equal('jumped line is 28', vim.api.nvim_win_get_cursor(0)[1], 28)

-- Fallback for non-luabind symbols
vim.cmd('edit ' .. vim.fn.fnameescape(game_lua_path))
vim.api.nvim_win_set_cursor(0, { 3, 8 }) -- On 'dmg'
local jumped_dmg = luabind.jump_to_definition({ bufnr = game_buf })
support.expect_equal('non-luabind symbol does not jump via luabind', jumped_dmg, false)

-- ── 7. Jump reference via user.jump ──────────────────────────────────────────
local ok_ref_calc = jump.jump_reference('calculate_damage', { path = demo_root })
support.expect_true('jump.jump_reference resolves calculate_damage', ok_ref_calc)
support.expect_equal('jump.jump_reference opens battle_bindings.cpp', vim.api.nvim_buf_get_name(0), cpp_bindings_path)
support.expect_equal('jump.jump_reference opens line 10', vim.api.nvim_win_get_cursor(0)[1], 10)

local ok_ref_heal = jump.jump_reference('Player#heal', { path = demo_root })
support.expect_true('jump.jump_reference resolves Player#heal', ok_ref_heal)
support.expect_equal('jump.jump_reference opens line 28', vim.api.nvim_win_get_cursor(0)[1], 28)

-- ── 8. Lua LSP (lua_ls) configuration & metadata generation ──────────────────
local fake_caps = {}
local lsp_cfg = user_lsp.lua_ls_config(fake_caps)
support.expect_equal('lua_ls runtime LuaJIT', lsp_cfg.settings.Lua.runtime.version, 'LuaJIT')
support.expect_true('lua_ls diagnostics has vim global', vim.tbl_contains(lsp_cfg.settings.Lua.diagnostics.globals, 'vim'))

local meta_dir = luabind.generate_meta_file(demo_root)
support.expect_true('meta_dir generated', meta_dir ~= nil and vim.fn.isdirectory(meta_dir) == 1)
local meta_file = vim.fs.joinpath(meta_dir, 'luabind_meta.lua')
support.expect_true('meta_file created', vim.fn.filereadable(meta_file) == 1)

local meta_content = table.concat(vim.fn.readfile(meta_file), '\n')
support.expect_true('meta_file has ---@meta', meta_content:find('%-%-%-@meta') ~= nil)
support.expect_true('meta_file declares Player class', meta_content:find('Player = {}') ~= nil)
support.expect_true('meta_file declares calculate_damage', meta_content:find('function calculate_damage') ~= nil)
support.expect_true('meta_file has body comments', meta_content:find('方法体注释：若触发暴击') ~= nil)

-- Test setup_lua_ls_workspace hook
local fake_new_config = {
  settings = {
    Lua = {
      workspace = {
        library = {},
      },
    },
  },
}
luabind.setup_lua_ls_workspace(fake_new_config, demo_root)
support.expect_true('meta_dir added to lua_ls workspace library', vim.tbl_contains(fake_new_config.settings.Lua.workspace.library, meta_dir))

-- ── 9. Mason ensures lua_ls ──────────────────────────────────────────────────
local mason_lspconfig_ok, mason_lspconfig = pcall(require, 'mason-lspconfig')
if mason_lspconfig_ok then
  local registry = require('mason-registry')
  support.expect_true('mason has lua-language-server package', registry.has_package('lua-language-server'))
end

-- ── 10. Call context parsing while writing luabind methods ───────────────────
local ctx1 = luabind.parse_call_context('calculate_damage(')
support.expect_equal('ctx1 func name', ctx1.func_name, 'calculate_damage')
support.expect_equal('ctx1 param idx', ctx1.param_idx, 1)

local ctx2 = luabind.parse_call_context('calculate_damage(10, ')
support.expect_equal('ctx2 func name', ctx2.func_name, 'calculate_damage')
support.expect_equal('ctx2 param idx', ctx2.param_idx, 2)

local ctx3 = luabind.parse_call_context('player:heal(')
support.expect_equal('ctx3 class name', ctx3.class_name, 'player')
support.expect_equal('ctx3 func name', ctx3.func_name, 'heal')
support.expect_equal('ctx3 param idx', ctx3.param_idx, 1)

local ctx4 = luabind.parse_call_context('calculate_damage(math.abs(-5), ')
support.expect_equal('ctx4 nested call param idx', ctx4.param_idx, 2)

local ctx_closed = luabind.parse_call_context('calculate_damage(1, 2)')
support.expect_equal('closed call returns nil', ctx_closed, nil)

-- ── 11. Floating call hint formatting and window display ─────────────────────
local hint_lines = luabind.format_call_hint(calc_method, 1)
local hint_text = table.concat(hint_lines, '\n')
support.expect_true('call hint contains signature', hint_text:find('int calculate_damage') ~= nil)
support.expect_true('call hint highlights param 1', hint_text:find('👉 %*%*参数 %(1/2%)%:%*%* `int attacker_id`') ~= nil)
support.expect_true('call hint contains method body comments', hint_text:find('方法体注释：若触发暴击') ~= nil)

luabind.show_call_hint({ method = calc_method, param_idx = 1 }, game_buf)
-- Verify that floating hint opened and can be closed cleanly
luabind.close_call_hint()

-- ── 12. SignatureHelp provider for luabind methods ───────────────────────────
vim.cmd('edit ' .. vim.fn.fnameescape(game_lua_path))
-- Place cursor on line 3 inside calculate_damage(
vim.api.nvim_win_set_cursor(0, { 3, 32 })
local sig_help = luabind.get_signature_help(game_buf)
support.expect_true('get_signature_help returns result', sig_help ~= nil)
support.expect_true('sig_help has signatures', #sig_help.signatures > 0)
support.expect_true('sig_help doc has body comments', sig_help.signatures[1].documentation.value:find('方法体注释：若触发暴击') ~= nil)

-- ── 13. Floating hint and hover inside .luabind files directly ───────────────
vim.cmd('edit ' .. vim.fn.fnameescape(cpp_bindings_path))
local cpp_buf = vim.api.nvim_get_current_buf()
support.expect_true('is_luabind_buffer returns true for cpp file in .luabind', luabind.is_luabind_buffer(cpp_buf))

luabind.attach_to_buffer(cpp_buf)
-- Check that hover mapping exists
support.expect_equal('cpp buffer has K mapping', vim.fn.maparg('K', 'n', false, true).desc, 'Hover (with luabind)')
support.expect_equal('cpp buffer has <leader>lh mapping', vim.fn.maparg('<leader>lh', 'n', false, true).desc, 'LSP: Hover (with luabind)')

-- Cursor on calculate_damage definition (line 10) in battle_bindings.cpp
vim.api.nvim_win_set_cursor(0, { 10, 10 })
local hover_in_cpp = luabind.show_hover({ bufnr = cpp_buf })
support.expect_true('show_hover succeeds inside .luabind file', hover_in_cpp)

support.flush()
print("All luabind and lua_ls tests completed successfully!")
