#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_PROJECT="${NVIM_TEST_JAVA_PROJECT:-$HOME/workspace/test-java}"

run_spec() {
  local spec="$1"
  echo "==> $spec"
  nvim --headless -u "$ROOT/init.lua" +"lua dofile('$ROOT/$spec')" +qa!
}

echo "==> startup smoke"
(cd "$ROOT" && nvim --headless '+qa')

run_spec "test/commenting_spec.lua"
run_spec "test/lsp_keymaps_spec.lua"
run_spec "test/select_spec.lua"
run_spec "test/jump_spec.lua"
run_spec "test/file_actions_spec.lua"
run_spec "test/xml_editing_spec.lua"
run_spec "test/dap_config_spec.lua"
run_spec "test/printf_highlight_spec.lua"

echo "==> test/java_file_actions_integration.lua"
NVIM_TEST_JAVA_PROJECT="$JAVA_PROJECT" nvim --headless -u "$ROOT/init.lua" +"lua dofile('$ROOT/test/java_file_actions_integration.lua')" +qa!
