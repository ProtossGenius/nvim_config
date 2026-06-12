# Copilot instructions for this repository

## Primary docs

- Start with `README.md` for the current feature set, test entrypoints, and packaging workflow.
- Use `docs/java-lsp-and-keymaps.zh-CN.md` when changing Java, LSP, or leader-key behavior; it is the detailed user-facing reference for those flows.

## Commands

Run commands from the repository root.

- Smoke test config startup: `nvim --headless '+qa'`
- Full regression suite: `./test/run_regression_suite.sh`
- Run a single headless spec: `nvim --headless -u "$PWD/init.lua" +"lua dofile('$PWD/test/select_spec.lua')" +qa!`
- Run the Java integration spec: `NVIM_TEST_JAVA_PROJECT="$PWD/test-projects/java17-spring-demo/core" nvim --headless -u "$PWD/init.lua" +"lua dofile('$PWD/test/java_file_actions_integration.lua')" +qa!`
- Package the config into an installer: `./package_nvim.sh` (writes `target/install.sh`)
- Show packaging help: `./package_nvim.sh -h`

## High-level architecture

- `init.lua` is the entrypoint. It bootstraps `lazy.nvim`, loads `user.options` and `user.keymaps`, then wires the repo's custom modules such as `user.util`, `user.templates`, `user.select`, and `user.printf_highlight`.
- `lua/user/plugins.lua` is the main integration layer for third-party plugins. Most behavior is either configured there directly or delegated into focused modules under `lua/user/`.
- LSP behavior is intentionally split: `lua/user/plugins.lua` assembles `lsp-zero`, `mason`, and `nvim-java`; `lua/user/lsp.lua` owns generic `on_attach` keymaps and formatting behavior; `lua/user/java.lua` owns JDTLS runtime detection, mapper-pair navigation, and Java-specific setup.
- Java buffers use the repository's own `ProtossGenius/java-lsp` binary, installed through `go install` into `stdpath('data')/java-lsp/bin/java-lsp`. `:JavaLspInstall` is the supported install/update entrypoint.
- File operations cross module boundaries: `lua/user/file_actions.lua` handles create/rename/delete for current buffers and Dirvish entries, while Java renames cooperate with JDTLS so type names, open buffers, and file notifications stay in sync.
- The config replaces several builtin/editor defaults with custom modules: `lua/user/select.lua` overrides `vim.ui.select`, `lua/user/comment.lua` adds Treesitter-aware commenting/textobjects, `lua/user/templates.lua` auto-populates new files, and `lua/user/llm/*` implements local-provider translation and ask flows.

## Key conventions

- Tests are plain Lua scripts under `test/`; they run through headless Neovim via `dofile(...)`, not via Plenary or Busted. Shared assertions/helpers live in `test/spec_support.lua`, and specs print results through `support.flush()`.
- When changing Java rename behavior, use `user.file_actions` instead of direct filesystem renames. The Java path depends on the server's real `textDocument/rename` plus `workspace/didRenameFiles` support so class names and references are updated semantically.
- `Mapper.java` and `Mapper.xml` pairing is a first-class feature in `user.java`. Changes to Java/XML navigation or LSP mappings should preserve mapper-aware jumps on `gf`, `gF`, `<C-]>`, and the related leader mappings for mapper buffers.
- Save-time formatting lives in `user.util` via a `BufWritePre` autocmd. It formats changed hunks when Gitsigns data exists, and it also runs Go organize-imports before write.
- `<leader>m` and `<F5>/<F6>/<F8>/<F9>` run `make` commands in the currently opened project directory through a terminal buffer. They are editor keymaps for whatever project is being edited, not maintenance commands for this Neovim config repo.
- `vim.ui.select` is expected to be the custom floating selector from `user.select`; preserve numeric jump, backspace rollback, `q`, and double-`<Esc>` behavior when touching selection UI.
- Local LLM features are wired to locally hosted providers from `lua/user/llm/config.lua` (`ollama` and a local OpenAI-compatible endpoint), not to a hosted SaaS plugin.
