local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

local project_root = vim.fn.stdpath('config') .. '/test-projects/java17-spring-demo'
local package_dir = project_root .. '/core/src/main/java/com/example/demo/es'
local suffix = tostring(os.time())
local class_name = 'EsCompletionProbe' .. suffix
local file_path = package_dir .. '/' .. class_name .. '.java'

_G.initial_cwd = project_root
vim.cmd('cd ' .. vim.fn.fnameescape(project_root))

vim.fn.mkdir(package_dir, 'p')
for _, stale_file in ipairs(vim.fn.glob(package_dir .. '/EsCompletionProbe*.java', false, true)) do
  vim.fn.delete(stale_file)
end

vim.fn.writefile({
  'package com.example.demo.es;',
  '',
  'import java.util.function.Function;',
  '',
  'import co.elastic.clients.elasticsearch._types.mapping.TypeMapping;',
  'import co.elastic.clients.util.ObjectBuilder;',
  '',
  'public class ' .. class_name .. ' {',
  '  private static final Function<TypeMapping.Builder, ObjectBuilder<TypeMapping>> VALUE = builder -> builder',
  '      .properties("name", property -> property.keyword(keyword -> keyword));',
  '',
  '  public void verifyCompletion() {',
  '    TypeMapping.Builder builder = new TypeMapping.Builder();',
  '    builder.',
  '  }',
  '}',
}, file_path)

local function completion_labels(result)
  local items = result and (result.items or result) or {}
  local labels = {}
  for _, item in ipairs(items) do
    table.insert(labels, item.label or item.insertText or '')
  end
  return labels
end

local function labels_include(labels, needle)
  for _, label in ipairs(labels) do
    if label:find(needle, 1, true) then
      return true
    end
  end
  return false
end

local function find_line_nr(needle)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for idx, line in ipairs(lines) do
    if line:find(needle, 1, true) then
      return idx
    end
  end
  error('Could not find line containing ' .. needle)
end

local function request_completion()
  local response_err = nil
  local response_result = nil
  local done = false
  local client = vim.lsp.get_clients({ bufnr = 0 })[1]
  local params = vim.lsp.util.make_position_params(0, client and client.offset_encoding or 'utf-16')

  vim.lsp.buf_request(0, 'textDocument/completion', params, function(err, result)
    response_err = err
    response_result = result
    done = true
  end)

  vim.wait(10000, function()
    return done
  end, 50)

  support.expect_true('java elasticsearch completion response received', done)
  support.expect_true('java elasticsearch completion request succeeds', response_err == nil)

  return completion_labels(response_result)
end

local function cleanup()
  local bufnr = vim.fn.bufnr(file_path)
  if bufnr > 0 then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
  vim.fn.delete(file_path)
end

local function run()
  vim.cmd('edit ' .. vim.fn.fnameescape(file_path))

  local attached = vim.wait(120000, function()
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
      if client.name == 'jdtls' then
        return true
      end
    end
    return false
  end, 200)

  support.expect_true('java elasticsearch completion jdtls attached', attached)

  local builder_completion_line = find_line_nr('    builder.')
  support.set_cursor_on_substring(builder_completion_line, 'builder.', 1, 7)
  support.feed('ap<Esc>')
  support.set_cursor_on_substring(builder_completion_line, 'builder.p', 1, 9)
  vim.wait(300)
  local builder_labels = request_completion()
  if not labels_include(builder_labels, 'properties') then
    error('java elasticsearch completion missing properties suggestion: ' .. vim.inspect(builder_labels))
  end
  support.expect_true('java elasticsearch completion suggests properties', true)

  vim.api.nvim_buf_set_lines(0, builder_completion_line - 1, builder_completion_line, false, { '    builder.' })
  vim.wait(300)

  support.set_cursor_on_substring(builder_completion_line, 'builder.', 1, 7)
  support.feed('ad<Esc>')
  support.set_cursor_on_substring(builder_completion_line, 'builder.d', 1, 9)
  vim.wait(300)
  local dynamic_templates_labels = request_completion()
  if not labels_include(dynamic_templates_labels, 'dynamicTemplates') then
    error('java elasticsearch completion missing dynamicTemplates suggestion: ' .. vim.inspect(dynamic_templates_labels))
  end
  support.expect_true('java elasticsearch completion suggests dynamicTemplates', true)
end

local ok, err = xpcall(run, debug.traceback)
cleanup()
if not ok then
  error(err)
end

support.flush()
