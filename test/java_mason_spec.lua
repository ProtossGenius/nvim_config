local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

local original_user_java = package.loaded['user.java']
local original_mason_registry = package.loaded['mason-registry']

local refresh_calls = 0
local install_calls = {}

package.loaded['user.java'] = nil
package.loaded['mason-registry'] = {
  refresh = function(callback)
    refresh_calls = refresh_calls + 1
    callback()
  end,
  get_package = function(name)
    return {
      is_installed = function()
        return false
      end,
      install = function()
        install_calls[name] = (install_calls[name] or 0) + 1
      end,
    }
  end,
}

local user_java = require('user.java')
user_java.ensure_mason_packages()
vim.wait(100)

support.expect_equal('java mason refreshes registry once', refresh_calls, 1)
support.expect_equal('java mason installs debug adapter when missing', install_calls['java-debug-adapter'], 1)

user_java.ensure_mason_packages()
vim.wait(100)

support.expect_equal('java mason only installs once per session', refresh_calls, 1)
support.expect_equal('java mason only queues one install per session', install_calls['java-debug-adapter'], 1)

local installed_install_attempted = false

package.loaded['user.java'] = nil
package.loaded['mason-registry'] = {
  refresh = function(callback)
    callback()
  end,
  get_package = function()
    return {
      is_installed = function()
        return true
      end,
      install = function()
        installed_install_attempted = true
      end,
    }
  end,
}

user_java = require('user.java')
user_java.ensure_mason_packages()
vim.wait(100)

support.expect_true('java mason skips installed debug adapter', not installed_install_attempted)

package.loaded['user.java'] = original_user_java
package.loaded['mason-registry'] = original_mason_registry

support.flush()
