-- Java LSP and DAP configuration using nvim-jdtls

local home = os.getenv("HOME")
local jdtls = require("jdtls")

-- 1. Detect root directory
local root_markers = { "gradlew", "pom.xml", "mvnw", ".git" }
local root_dir = require("jdtls.setup").find_root(root_markers)

if root_dir == "" then
  return
end

-- 2. Define workspace directory for JDTLS
local project_name = vim.fn.fnamemodify(root_dir, ":t")
local workspace_dir = home .. "/.local/share/nvim/jdtls-workspace/" .. project_name

-- 3. JDTLS Executable check
local jdtls_bin = home .. "/.local/share/nvim/mason/bin/jdtls"
if vim.fn.executable(jdtls_bin) == 0 then
  vim.notify("JDTLS executable not found. Please run :MasonInstall jdtls java-debug-adapter java-test", vim.log.levels.WARN)
  return
end

-- 4. Locate Debug and Test Bundles (installed via Mason)
local bundles = {}
local mason_path = vim.fn.stdpath("data") .. "/mason/packages"

-- Path for java-debug-adapter
local debug_bundle_path = mason_path .. "/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar"
local debug_bundles = vim.fn.glob(debug_bundle_path, true)
if debug_bundles ~= "" then
  table.insert(bundles, debug_bundles)
else
  vim.notify("Java Debug Adapter bundle not found. Run :MasonInstall java-debug-adapter to enable debugging.", vim.log.levels.INFO)
end

-- Path for java-test (optional helper)
local test_bundle_path = mason_path .. "/java-test/extension/server/*.jar"
local test_bundles = vim.fn.glob(test_bundle_path, true)
if test_bundles ~= "" then
  for _, bundle in ipairs(vim.split(test_bundles, "\n")) do
    if bundle ~= "" then
      table.insert(bundles, bundle)
    end
  end
end

-- 4.5 Locate or download Lombok jar
local lombok_jar = ""
local lombok_m2_glob = home .. "/.m2/repository/org/projectlombok/lombok/*/lombok-*.jar"
local lombok_m2_files = vim.fn.glob(lombok_m2_glob, true)
if lombok_m2_files ~= "" then
  local file_list = vim.split(lombok_m2_files, "\n")
  lombok_jar = file_list[#file_list]
end

if lombok_jar == "" then
  local lombok_fallback_dir = home .. "/.local/share/nvim"
  local lombok_fallback_path = lombok_fallback_dir .. "/lombok.jar"
  if vim.fn.filereadable(lombok_fallback_path) == 0 then
    vim.notify("Downloading Lombok jar for JDTLS...", vim.log.levels.INFO)
    vim.fn.mkdir(lombok_fallback_dir, "p")
    vim.fn.system({
      "curl", "-sL",
      "https://repo1.maven.org/maven2/org/projectlombok/lombok/1.18.34/lombok-1.18.34.jar",
      "-o", lombok_fallback_path
    })
  end
  lombok_jar = lombok_fallback_path
end

-- 5. Build Configuration
local cmd = {
  jdtls_bin,
  "-data", workspace_dir
}
if lombok_jar ~= "" then
  table.insert(cmd, "--jvm-arg=-javaagent:" .. lombok_jar)
end

local config = {
  cmd = cmd,
  root_dir = root_dir,
  settings = {
    java = {
      signatureHelp = { enabled = true },
      contentProvider = { preferred = "fernflower" },
      completion = {
        favoriteStaticMembers = {
          "org.hamcrest.MatcherAssert.assertThat",
          "org.hamcrest.Matchers.*",
          "org.hamcrest.CoreMatchers.*",
          "org.junit.jupiter.api.Assertions.*",
          "java.util.Objects.requireNonNull",
          "java.util.Objects.requireNonNullElse",
          "org.mockito.Mockito.*"
        },
        filteredTypes = {
          "com.sun.*",
          "sun.*",
          "jdk.*",
          "org.graalvm.*",
          "oracle.*"
        }
      },
      sources = {
        organizeImports = {
          starThreshold = 9999,
          staticStarThreshold = 9999,
        },
      },
      codeGeneration = {
        toString = {
          template = "${object.className}[#${member.name()}=${member.value}, ${otherMembers}]"
        },
        useBlocks = true,
      }
    }
  },
  init_options = {
    bundles = bundles
  },
  on_attach = function(client, bufnr)
    -- Initialize DAP (Java Debugger) when LSP attaches
    jdtls.setup_dap({ hotcodereplace = "auto" })
    
    -- standard LSP Keymaps inside java buffers
    local opts = { silent = true, buffer = bufnr }
    vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
    vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
    vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, opts)
    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
    vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
    vim.keymap.set("n", "<leader>f", function() vim.lsp.buf.format { async = true } end, opts)

    -- Jdtls specific keymaps
    vim.keymap.set("n", "<leader>co", jdtls.organize_imports, { desc = "Java: Organize Imports", buffer = bufnr })
    vim.keymap.set("n", "<leader>ct", jdtls.test_class, { desc = "Java: Test Class", buffer = bufnr })
    vim.keymap.set("n", "<leader>cn", jdtls.test_nearest_method, { desc = "Java: Test Nearest Method", buffer = bufnr })
    vim.keymap.set("n", "<leader>cxv", jdtls.extract_variable, { desc = "Java: Extract Variable", buffer = bufnr })
    vim.keymap.set("v", "<leader>cxv", function() jdtls.extract_variable(true) end, { desc = "Java: Extract Variable", buffer = bufnr })
    vim.keymap.set("n", "<leader>cxc", jdtls.extract_constant, { desc = "Java: Extract Constant", buffer = bufnr })
    vim.keymap.set("v", "<leader>cxc", function() jdtls.extract_constant(true) end, { desc = "Java: Extract Constant", buffer = bufnr })
  end
}

-- 6. Start or attach the LSP client
jdtls.start_or_attach(config)
