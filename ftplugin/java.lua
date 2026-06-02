-- Java LSP and DAP configuration using nvim-jdtls

local home = os.getenv("HOME")
local jdtls = require("jdtls")

-- 1. Detect root directory using the custom project_root calculation
local user_java = require("user.java")
local root_dir = user_java._test.project_root(0)

if not root_dir or root_dir == "" then
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
local test_bundle_path = mason_path .. "/java-test/extension/server/com.microsoft.java.test.plugin-*.jar"
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

-- 4.8 Dynamic macOS JVM runtime scanner
local runtimes = _G._user_jvm_runtimes

if not runtimes then
  runtimes = {}
  local seen_runtimes = {}

  local function add_jvm_runtime(path)
    if not path or path == "" then return end
    path = vim.fs.normalize(path)
    if seen_runtimes[path] then return end

    local java_bin = path .. "/bin/java"
    if vim.fn.executable(java_bin) == 1 then
      local major_version = nil
      local release_file = path .. "/release"
      local f = io.open(release_file, "r")
      if f then
        for line in f:lines() do
          local ver_str = line:match('^JAVA_VERSION="([^"]+)"')
          if ver_str then
            local major = ver_str:match('^(%d+)')
            if major == '1' then
              major = ver_str:match('^1%.(%d+)')
            end
            major_version = tonumber(major)
            break
          end
        end
        f:close()
      end

      if not major_version then
        local match = path:match("openjdk@(%d+)") or path:match("java-(%d+)") or path:match("jdk-(%d+)") or path:match("zulu-(%d+)")
        if match then
          major_version = tonumber(match)
        end
      end

      if major_version then
        local name = major_version == 8 and "JavaSE-1.8" or ("JavaSE-" .. major_version)
        table.insert(runtimes, {
          name = name,
          path = path,
        })
        seen_runtimes[path] = true
      end
    end
  end

  local scan_globs = {
    "/Library/Java/JavaVirtualMachines/*/Contents/Home",
    home .. "/.sdkman/candidates/java/*",
    "/opt/homebrew/Cellar/openjdk*/*/libexec/openjdk.jdk/Contents/Home",
    "/opt/homebrew/opt/openjdk*/libexec/openjdk.jdk/Contents/Home",
    "/usr/lib/jvm/*",
    home .. "/.local/share/nvim/nvim-java/packages/openjdk/*/jdk-*/Contents/Home",
    home .. "/.local/share/nvim/nvim-java/packages/openjdk/*/jdk-*"
  }

  for _, pattern in ipairs(scan_globs) do
    local paths = vim.fn.glob(pattern, true, true)
    for _, p in ipairs(paths) do
      if p ~= "" then
        add_jvm_runtime(p)
      end
    end
  end

  _G._user_jvm_runtimes = runtimes
end

-- 5. Build Configuration
local cmd = {
  jdtls_bin,
  "-data", workspace_dir
}
if lombok_jar ~= "" then
  table.insert(cmd, "--jvm-arg=-javaagent:" .. lombok_jar)
end

local java_settings = {
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

if #runtimes > 0 then
  java_settings.configuration = {
    runtimes = runtimes,
  }
end

local config = {
  cmd = cmd,
  root_dir = root_dir,
  settings = {
    java = java_settings
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
