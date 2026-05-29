local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
local user_dap = require('user.dap')

local temp_root = vim.fn.tempname()
vim.fn.mkdir(temp_root, 'p')
temp_root = vim.uv.fs_realpath(temp_root) or vim.fs.normalize(temp_root)
vim.cmd('cd ' .. vim.fn.fnameescape(temp_root))

local source_path = vim.fs.normalize(temp_root .. '/main.py')
vim.fn.writefile({ 'print("hello")' }, source_path)
vim.cmd('edit ' .. vim.fn.fnameescape(source_path))

local config_path = vim.fs.normalize(temp_root .. '/.nvim-dap.json')
vim.fn.writefile({
  '<projectDescription>',
  '  <name>temp-eclipse-project</name>',
  '</projectDescription>',
}, temp_root .. '/.project')
vim.fn.writefile({
  '<project xmlns="http://maven.apache.org/POM/4.0.0">',
  '  <modelVersion>4.0.0</modelVersion>',
  '  <groupId>com.example</groupId>',
  '  <artifactId>temp-artifact</artifactId>',
  '  <name>temp-name</name>',
  '</project>',
}, temp_root .. '/pom.xml')

user_dap.edit_config(0)

local generated = vim.json.decode(table.concat(vim.fn.readfile(config_path), '\n'))
support.expect_equal('dap edit creates default attach config', generated.configurations[1].request, 'attach')
support.expect_equal('dap edit creates attach port default', generated.configurations[1].port, 5005)
support.expect_equal('dap edit fills attach main class', generated.configurations[1].mainClass, 'com.example.Main')
support.expect_equal('dap edit creates default launch config', generated.configurations[2].request, 'launch')
support.expect_equal('dap edit fills detected main class', generated.configurations[2].mainClass, 'com.example.Main')
support.expect_equal('dap edit keeps desc short', generated._desc, 'Default launch + port configs generated from the current build files.')
support.expect_equal('dap edit includes detected maven artifact', generated._detected.maven.artifactId, 'temp-artifact')
support.expect_equal('dap edit includes detected eclipse name', generated._detected.eclipse.projectName, 'temp-eclipse-project')
support.expect_equal('dap edit detects build tool', generated._detected.buildTool, 'maven')

generated.configurations = {
  {
    name = 'Run current file',
    type = 'python',
    request = 'launch',
    program = '${file}',
    cwd = '${projectRoot}',
    args = { '--flag' },
  },
}
vim.fn.writefile(vim.split(vim.json.encode(generated), '\n', { plain = true }), config_path)

local captured
local original_dap = package.loaded['dap']
package.loaded['dap'] = {
  run = function(config)
    captured = config
  end,
  toggle_breakpoint = function() end,
}

user_dap.start(0)

support.expect_true('dap start passes config to dap.run', captured ~= nil)
support.expect_equal('dap start preserves config name', captured.name, 'Run current file')
support.expect_equal('dap start expands file placeholder', captured.program, source_path)
support.expect_equal('dap start expands project root placeholder', captured.cwd, temp_root)
support.expect_equal('dap start preserves args array', captured.args[1], '--flag')

generated.configurations = {
  {
    name = 'Attach port',
    type = 'java',
    request = 'attach',
    hostName = '127.0.0.1',
    port = 5005,
  },
}
vim.fn.writefile(vim.split(vim.json.encode(generated), '\n', { plain = true }), config_path)

local original_notify = vim.notify
local original_java = package.loaded['java']
local original_get_clients = vim.lsp.get_clients
local warned
captured = nil

vim.notify = function(message)
  warned = message
end
package.loaded['java'] = {
  dap = {
    config_dap = function()
    end,
  },
}
vim.lsp.get_clients = function()
  return {
    {
      config = {
        root_dir = temp_root,
      },
      workspace_folders = {},
    },
  }
end

user_dap.start(0)

support.expect_equal('dap java attach keeps adapter type', captured.type, 'java')
support.expect_equal('dap java attach does not warn with jdtls', warned, nil)

vim.notify = original_notify
package.loaded['java'] = original_java
vim.lsp.get_clients = original_get_clients

warned = nil
captured = nil
vim.notify = function(message)
  warned = message
end
package.loaded['java'] = {
  dap = {
    config_dap = function()
      error('config_dap should not run without jdtls')
    end,
  },
}
vim.lsp.get_clients = function()
  return {}
end

user_dap.start(0)

support.expect_equal('dap java attach warns when jdtls is missing', warned, 'Java debug requires an active jdtls client. Open a Java file in this project first, wait for jdtls to attach, then retry.')
support.expect_equal('dap java attach skips dap.run when jdtls is missing', captured, nil)

vim.notify = original_notify
package.loaded['java'] = original_java
vim.lsp.get_clients = original_get_clients

generated.configurations = {
  {
    name = 'Launch app',
    type = 'java',
    request = 'launch',
    mainClass = 'com.example.demo.DemoApplication',
  },
}
vim.fn.writefile(vim.split(vim.json.encode(generated), '\n', { plain = true }), config_path)

warned = nil
captured = nil
vim.notify = function(message)
  warned = message
end
package.loaded['java'] = {
  dap = {
    config_dap = function()
      error('config_dap should not run without jdtls')
    end,
  },
}
vim.lsp.get_clients = function()
  return {}
end

user_dap.start(0)

support.expect_equal('dap java launch warns when jdtls is missing', warned, 'Java debug requires an active jdtls client. Open a Java file in this project first, wait for jdtls to attach, then retry.')
support.expect_equal('dap java launch skips dap.run when jdtls is missing', captured, nil)

local java_source_path = vim.fs.normalize(temp_root .. '/src/main/java/com/example/Main.java')
vim.fn.mkdir(vim.fn.fnamemodify(java_source_path, ':h'), 'p')
vim.fn.writefile({
  'package com.example;',
  '',
  'public class Main {',
  '  public static void main(String[] args) {}',
  '}',
}, java_source_path)
local java_bufnr = vim.fn.bufadd(java_source_path)
vim.fn.bufload(java_bufnr)
vim.bo[java_bufnr].filetype = 'java'

local configured_from
warned = nil
captured = nil
vim.notify = function(message)
  warned = message
end
package.loaded['java'] = {
  dap = {
    config_dap = function()
      configured_from = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
    end,
  },
}
vim.lsp.get_clients = function()
  return {
    {
      name = 'jdtls',
      config = {
        root_dir = temp_root,
      },
      workspace_folders = {},
    },
  }
end

vim.cmd('enew!')
vim.api.nvim_buf_set_name(0, 'jdt:/contents/java.base/java.lang.String.class')
vim.bo.filetype = 'java'
user_dap.start(0)

support.expect_equal('dap java launch from jdt buffer does not warn', warned, nil)
support.expect_equal('dap java launch from jdt buffer still runs', captured and captured.type, 'java')
support.expect_equal('dap java launch from jdt buffer configures real project java buffer', configured_from, java_source_path)

vim.notify = original_notify
package.loaded['java'] = original_java
vim.lsp.get_clients = original_get_clients
package.loaded['dap'] = original_dap
vim.cmd('bdelete!')
vim.fn.delete(temp_root, 'rf')

support.flush()
