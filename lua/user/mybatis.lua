local uv = vim.uv or vim.loop

local M = {}

local java_markers = {
  'pom.xml',
  'mvnw',
  'build.gradle',
  'build.gradle.kts',
  'settings.gradle',
  'settings.gradle.kts',
  'gradlew',
}

local function is_file(path)
  local stat = path and path ~= '' and uv.fs_stat(path) or nil
  return stat and stat.type == 'file' or false
end

function M.is_java_project_root(root)
  if not root or root == '' or root == '/' then
    return false
  end

  for _, marker in ipairs(java_markers) do
    if is_file(vim.fs.joinpath(root, marker)) then
      return true
    end
  end

  return false
end

function M.patch_virtual_sync()
  local ok, sync = pcall(require, 'mybatis-xml.virtual.sync')
  if not ok or sync._user_java_root_guard then
    return sync
  end

  local original_generate_all = sync.generate_all
  sync.generate_all = function(...)
    local root = require('mybatis-xml.project').root()
    if not M.is_java_project_root(root) then
      return
    end
    return original_generate_all(...)
  end

  sync._user_java_root_guard = true
  return sync
end

function M.setup(opts)
  M.patch_virtual_sync()
  require('mybatis-xml').setup(opts)
end

M._test = {
  java_markers = java_markers,
}

return M
