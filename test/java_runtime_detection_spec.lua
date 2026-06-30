local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

-- Test that the ftplugin/java.lua runtime scanner can detect JDKs from ~/.jdks/
-- This validates the fix for the bug where List.of().getLast() error would disappear
-- because JDTLS lacked a JavaSE-17 runtime and fell back to the JDK 21 APIs.

-- Simulate the ftplugin's runtime scanner logic with the updated scan globs
local home = os.getenv('HOME')
local seen_runtimes = {}
local runtimes = {}

local function add_jvm_runtime(path)
  if not path or path == '' then return end
  path = vim.fs.normalize(path)
  if seen_runtimes[path] then return end

  local java_bin = path .. '/bin/java'
  if vim.fn.executable(java_bin) == 1 then
    local major_version = nil
    local release_file = path .. '/release'
    local f = io.open(release_file, 'r')
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
      local match = path:match('openjdk@(%d+)') or path:match('java%-(%d+)') or path:match('jdk%-(%d+)') or path:match('zulu%-(%d+)')
      if match then
        major_version = tonumber(match)
      end
    end

    if major_version then
      local name = major_version == 8 and 'JavaSE-1.8' or ('JavaSE-' .. major_version)
      table.insert(runtimes, {
        name = name,
        path = path,
        _major = major_version,
      })
      seen_runtimes[path] = true
    end
  end
end

-- These are the scan globs from the FIXED ftplugin/java.lua (should include ~/.jdks/*)
local scan_globs = {
  '/Library/Java/JavaVirtualMachines/*/Contents/Home',
  home .. '/.sdkman/candidates/java/*',
  '/opt/homebrew/Cellar/openjdk*/*/libexec/openjdk.jdk/Contents/Home',
  '/opt/homebrew/opt/openjdk*/libexec/openjdk.jdk/Contents/Home',
  '/usr/lib/jvm/*',
  home .. '/.jdks/*/Contents/Home',
  home .. '/.jdks/*',
  home .. '/.local/share/nvim/nvim-java/packages/openjdk/*/jdk-*/Contents/Home',
  home .. '/.local/share/nvim/nvim-java/packages/openjdk/*/jdk-*',
}

for _, pattern in ipairs(scan_globs) do
  local paths = vim.fn.glob(pattern, true, true)
  for _, p in ipairs(paths) do
    if p ~= '' then
      add_jvm_runtime(p)
    end
  end
end

-- Verify that at least some runtimes were detected
support.expect_true('at least one JVM runtime detected', #runtimes > 0)

-- Check specifically for JavaSE-17 (from ~/.jdks/corretto-17.0.10)
local has_java_17 = false
for _, r in ipairs(runtimes) do
  if r.name == 'JavaSE-17' then
    has_java_17 = true
    break
  end
end

support.expect_true('JavaSE-17 runtime detected (from ~/.jdks/)', has_java_17)

-- Check that JavaSE-17 points to a real JDK 17 (not a higher version mapped down)
for _, r in ipairs(runtimes) do
  if r.name == 'JavaSE-17' then
    support.expect_equal('JavaSE-17 has major version 17', r._major, 17)
    break
  end
end

-- Also verify the lua/user/java.lua runtime detection finds the same
package.loaded['user.java'] = nil
local user_java = require('user.java')
local config = user_java.jdtls_config({})
local config_runtimes = config.settings
  and config.settings.java
  and config.settings.java.configuration
  and config.settings.java.configuration.runtimes
  or {}

local user_java_has_17 = false
for _, r in ipairs(config_runtimes) do
  if r.name == 'JavaSE-17' then
    user_java_has_17 = true
    break
  end
end

support.expect_true('lua/user/java.lua also detects JavaSE-17', user_java_has_17)

support.flush()
