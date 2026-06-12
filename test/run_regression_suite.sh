#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_PROJECT="${NVIM_TEST_JAVA_PROJECT:-$ROOT/test-projects/java17-spring-demo/core}"

run_spec() {
  local spec="$1"
  echo "==> $spec"
  nvim --headless -u "$ROOT/init.lua" +"lua local ok,err = pcall(dofile, '$ROOT/$spec'); for _, c in ipairs(vim.lsp.get_clients()) do pcall(function() c:terminate() end) end; if not ok then print(err); vim.cmd('cquit') else vim.cmd('qa!') end"
}

echo "==> startup smoke"
(cd "$ROOT" && nvim --headless '+qa')

echo "==> install java-lsp"
nvim --headless -u "$ROOT/init.lua" +"lua require('user.java').ensure_java_lsp_installed({ force = true, notify = false })" +qa!

run_spec "test/commenting_spec.lua"
run_spec "test/lsp_keymaps_spec.lua"
run_spec "test/select_spec.lua"
run_spec "test/jump_spec.lua"
run_spec "test/file_actions_spec.lua"
run_spec "test/xml_editing_spec.lua"
run_spec "test/mybatis_plugin_integration_spec.lua"
run_spec "test/dap_config_spec.lua"
run_spec "test/dap_keymaps_spec.lua"
run_spec "test/dap_cpp_spec.lua"
run_spec "test/cpp_keymap_scope_spec.lua"
run_spec "test/java_autostart_spec.lua"
run_spec "test/java_double_layer_autostart_spec.lua"
run_spec "test/java_navigation_spec.lua"
run_spec "test/java_completion_spec.lua"
run_spec "test/java_diagnostics_spec.lua"
run_spec "test/java_signature_help_spec.lua"
run_spec "test/printf_highlight_spec.lua"
run_spec "test/scratchpad_spec.lua"
run_spec "test/telescope_path_spec.lua"

echo "==> test/java_file_actions_integration.lua"
NVIM_TEST_JAVA_PROJECT="$JAVA_PROJECT" nvim --headless -u "$ROOT/init.lua" +"lua local ok,err = pcall(dofile, '$ROOT/test/java_file_actions_integration.lua'); for _, c in ipairs(vim.lsp.get_clients()) do pcall(function() c:terminate() end) end; if not ok then print(err); vim.cmd('cquit') else vim.cmd('qa!') end"
