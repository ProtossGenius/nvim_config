-- Overrides mason.nvim's official `jdtls` package to install a custom-built
-- distribution that fixes 2-3 level nested lambda completion (see
-- eclipse.jdt.core@4969cad78b8f796479a56a9be90e1ed4b00fafee).
--
-- The archive is hosted on the `dist/jdtls-nested-lambda-fix` branch of
-- https://github.com/ProtossGenius/eclipse.jdt.ls and served via
-- raw.githubusercontent.com. See dist/README.md on that branch for details
-- on what changed and how it was built.
--
-- Registered in lua/user/plugins.lua via:
--   require('mason').setup({
--     registries = { 'lua:user.mason_registry_jdtls_fix', 'github:mason-org/mason-registry' },
--   })
-- Placing our `lua:` registry first means this spec shadows the upstream
-- `jdtls` package definition (mason-registry/init.lua returns the first
-- match across registries, in order).

local DIST_URL = "https://raw.githubusercontent.com/ProtossGenius/eclipse.jdt.ls/"
  .. "dist/jdtls-nested-lambda-fix/dist/jdtls-nested-lambda-fix-linux-x64.tar.gz"

---@type RegistryPackageSpec
return {
  schema = "registry+v1",
  name = "jdtls",
  description = "Java language server (custom build: fixes nested-lambda completion).",
  homepage = "https://github.com/ProtossGenius/eclipse.jdt.ls",
  licenses = { "EPL-2.0" },
  languages = { "Java" },
  categories = { "LSP" },
  source = {
    id = "pkg:generic/ProtossGenius/eclipse.jdt.ls@nested-lambda-fix",
    download = {
      {
        target = { "darwin_x64", "darwin_arm64" },
        files = {
          ["jdtls.tar.gz"] = DIST_URL,
          ["lombok.jar"] = "https://projectlombok.org/downloads/lombok.jar",
        },
        config = "config_mac/",
      },
      {
        target = "linux",
        files = {
          ["jdtls.tar.gz"] = DIST_URL,
          ["lombok.jar"] = "https://projectlombok.org/downloads/lombok.jar",
        },
        config = "config_linux/",
      },
      {
        target = "win",
        files = {
          ["jdtls.tar.gz"] = DIST_URL,
          ["lombok.jar"] = "https://projectlombok.org/downloads/lombok.jar",
        },
        config = "config_win/",
      },
    },
  },
  schemas = {
    lsp = "vscode:https://raw.githubusercontent.com/redhat-developer/vscode-java/master/package.json",
  },
  bin = {
    jdtls = "python:bin/jdtls",
  },
  share = {
    ["jdtls/lombok.jar"] = "lombok.jar",
    ["jdtls/plugins/"] = "plugins/",
    ["jdtls/config/"] = "{{source.download.config}}",
  },
  neovim = {
    lspconfig = "jdtls",
  },
}
