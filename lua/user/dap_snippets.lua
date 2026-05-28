local M = {}

local loaded = false

local function in_dap_config()
  return vim.fs.basename(vim.api.nvim_buf_get_name(0)) == '.nvim-dap.json'
end

function M.setup()
  if loaded then
    return
  end

  local ls = require('luasnip')
  local fmt = require('luasnip.extras.fmt').fmt
  local insert = ls.insert_node
  local snippet = ls.snippet

  ls.add_snippets('json', {
    snippet({
      trig = 'port',
      name = 'Java attach by port',
      dscr = 'Expand a Java attach-by-port config',
      condition = in_dap_config,
    }, fmt([[
{{
  "name": "{}",
  "type": "java",
  "request": "attach",
  "hostName": "{}",
  "port": {},
  "projectName": "{}"
}}]], {
      insert(1, 'port-5005'),
      insert(2, '127.0.0.1'),
      insert(3, '5005'),
      insert(4, 'demo'),
    })),
    snippet({
      trig = 'launch',
      name = 'Java launch',
      dscr = 'Expand a Java launch config',
      condition = in_dap_config,
    }, fmt([[
{{
  "name": "{}",
  "type": "java",
  "request": "launch",
  "cwd": "${{projectRoot}}",
  "projectName": "{}",
  "mainClass": "{}",
  "args": [
    "{}"
  ]
}}]], {
      insert(1, 'launch'),
      insert(2, 'demo'),
      insert(3, 'com.example.demo.DemoApplication'),
      insert(4, '--spring.profiles.active=dev'),
    })),
  })

  loaded = true
end

return M
