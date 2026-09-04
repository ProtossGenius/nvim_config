#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_PROJECT="${NVIM_TEST_JAVA_PROJECT:-$HOME/workspace/test-java}"

if [ ! -d "$JAVA_PROJECT" ]; then
  echo "Setting up temporary test-java project..."
  mkdir -p "$JAVA_PROJECT"
  cp -r "$ROOT/test-projects/java17-spring-demo/core/"* "$JAVA_PROJECT/"
fi

run_spec() {
  local spec="$1"
  echo "==> $spec"
  nvim --headless -u "$ROOT/init.lua" +"lua local ok,err = pcall(dofile, '$ROOT/$spec'); for _, c in ipairs(vim.lsp.get_clients()) do pcall(function() c:terminate() end) end; if not ok then print(err); vim.cmd('cquit') else vim.cmd('qa!') end"
}

echo "==> startup smoke"
(cd "$ROOT" && nvim --headless '+qa')

run_spec "test/commenting_spec.lua"
run_spec "test/lsp_keymaps_spec.lua"
run_spec "test/cmp_options_spec.lua"
run_spec "test/select_spec.lua"
run_spec "test/jump_spec.lua"
run_spec "test/file_actions_spec.lua"
run_spec "test/xml_editing_spec.lua"
run_spec "test/mybatis_startup_guard_spec.lua"
run_spec "test/mybatis_plugin_integration_spec.lua"
run_spec "test/dap_config_spec.lua"
run_spec "test/dap_keymaps_spec.lua"
run_spec "test/dap_interactive_spec.lua"
run_spec "test/dap_completion_and_extract_spec.lua"
run_spec "test/dap_cpp_spec.lua"
run_spec "test/cpp_keymap_scope_spec.lua"
run_spec "test/java_autostart_spec.lua"
run_spec "test/java_double_layer_autostart_spec.lua"
run_spec "test/java_single_instance_spec.lua"
run_spec "test/java_runtime_detection_spec.lua"
run_spec "test/java_signature_help_spec.lua"
run_spec "test/printf_highlight_spec.lua"
run_spec "test/scratchpad_spec.lua"
run_spec "test/telescope_path_spec.lua"
run_spec "test/telescope_find_files_spec.lua"
run_spec "test/java_class_search_spec.lua"

run_spec "test/java_file_actions_integration.lua"
run_spec "test/java_stale_diagnostics_integration.lua"
run_spec "test/java_override_methods_integration.lua"
