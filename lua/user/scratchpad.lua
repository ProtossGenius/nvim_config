local M = {}

local uv = vim.uv or vim.loop
local output_buf = nil
local output_win = nil
local OUTPUT_START_MARKER = '============ output start ==============='
local OUTPUT_END_MARKER = '============ output end ================='

local function normalize(path)
  if not path or path == '' then
    return nil
  end

  return vim.fs.normalize(path)
end

local function is_file(path)
  local stat = path and path ~= '' and uv.fs_stat(path) or nil
  return stat and stat.type == 'file' or false
end

local function trim_trailing_blank_lines(lines)
  while #lines > 0 and lines[#lines] == '' do
    table.remove(lines)
  end
end

local function strip_output_block(lines)
  local clean_lines = {}
  local i = 1

  while i <= #lines do
    if lines[i]:match('^/%*%*%*%*%* result %*%*%*%*') then
      i = i + 1
      while i <= #lines and not lines[i]:match('^%*%*+ output end %*+') do
        i = i + 1
      end
      if i <= #lines then
        i = i + 1
      end
      trim_trailing_blank_lines(clean_lines)
    elseif lines[i] == '/*' and lines[i + 1] == OUTPUT_START_MARKER then
      i = i + 2
      while i <= #lines and lines[i] ~= OUTPUT_END_MARKER do
        i = i + 1
      end
      if i <= #lines and lines[i] == OUTPUT_END_MARKER then
        i = i + 1
      end
      if i <= #lines and lines[i] == '*/' then
        i = i + 1
      end
      trim_trailing_blank_lines(clean_lines)
    else
      table.insert(clean_lines, lines[i])
      i = i + 1
    end
  end

  return clean_lines
end

local function sanitize_output_line(line)
  if line == OUTPUT_START_MARKER or line == OUTPUT_END_MARKER then
    return ' ' .. line
  end

  return (line:gsub('%*/', '* /'))
end

local function starts_with_path(path, root)
  return path == root or path:sub(1, #root + 1) == root .. '/'
end

local function find_jdtls_client(path)
  local normalized_path = normalize(path)
  if not normalized_path then
    return nil
  end

  local best_client
  local best_root_len = -1
  for _, client in ipairs(vim.lsp.get_clients({ name = 'jdtls' })) do
    local roots = {}

    if client.config and client.config.root_dir then
      table.insert(roots, client.config.root_dir)
    end

    for _, folder in ipairs(client.workspace_folders or {}) do
      if folder.uri then
        table.insert(roots, vim.uri_to_fname(folder.uri))
      end
    end

    for _, root in ipairs(roots) do
      local normalized_root = normalize(root)
      if normalized_root and starts_with_path(normalized_path, normalized_root) and #normalized_root > best_root_len then
        best_client = client
        best_root_len = #normalized_root
      end
    end
  end

  return best_client
end

local function get_java_classpath(client, bufnr, file_path, callback)
  local uri = vim.uri_from_fname(file_path)

  local function finish(classpaths)
    if type(classpaths) == 'table' and #classpaths > 0 then
      callback(classpaths)
      return
    end

    callback(nil)
  end

  local function request_classpaths(scope)
    client:request('workspace/executeCommand', {
      command = 'java.project.getClasspaths',
      arguments = { uri, vim.fn.json_encode({ scope = scope }) },
    }, function(err, resp)
      vim.schedule(function()
        if err then
          finish(nil)
          return
        end

        finish(resp and resp.classpaths or nil)
      end)
    end, bufnr)
  end

  client:request('workspace/executeCommand', {
    command = 'java.project.isTestFile',
    arguments = { uri },
  }, function(err, is_test_file)
    vim.schedule(function()
      if err then
        request_classpaths('runtime')
        return
      end

      request_classpaths(is_test_file and 'test' or 'runtime')
    end)
  end, bufnr)
end

-- 获取当前 Java 文件的 package 声明
local function get_java_package(bufnr, file_path)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, l in ipairs(lines) do
    local pkg = l:match('^%s*package%s+([%w_%.]+)%s*;')
    if pkg then
      return pkg
    end
  end
  local relative = file_path:match('src/[^/]+/java/(.+)$')
  if relative then
    local dir = vim.fn.fnamemodify(relative, ':h')
    return dir:gsub('/', '.')
  end
  return 'com.example.demo'
end

-- 获取适合的临时文件名与模板
local function get_scratch_template(bufnr, current_path, filetype)
  local dir = vim.fn.fnamemodify(current_path, ':h')
  if dir == '' or not uv.fs_stat(dir) then
    dir = vim.fn.getcwd()
  end

  if filetype == 'java' then
    local package = get_java_package(bufnr, current_path)
    local file_path = vim.fs.joinpath(dir, 'Scratchpad.java')
    local template = {
      '// [快捷键]: 在 Normal 模式下按 <leader>r 或 <CR> 快速编译并运行该代码片段！',
      'package ' .. package .. ';',
      'import java.util.*;',
      'import java.math.*;',
      'import java.time.*;',
      '',
      'public class Scratchpad {',
      '    public static void main(String[] args) {',
      '        // 在此编写 Java 临时验证代码 (例如 List.of("A", "B").getLast())',
      '        ',
      '    }',
      '}'
    }
    return file_path, template, 10
  elseif filetype == 'cpp' then
    local file_path = vim.fs.joinpath(dir, 'scratchpad.cpp')
    local template = {
      '// [快捷键]: 在 Normal 模式下按 <leader>r 或 <CR> 快速编译并运行该代码片段！',
      '#include <iostream>',
      '#include <vector>',
      '#include <string>',
      '#include <algorithm>',
      '#include <map>',
      '#include <set>',
      'using namespace std;',
      '',
      'int main() {',
      '    // 在此编写 C++ 临时验证代码',
      '    ',
      '    return 0;',
      '}'
    }
    return file_path, template, 12
  elseif filetype == 'go' then
    local file_path = vim.fs.joinpath(dir, 'scratchpad.go')
    local template = {
      '// [快捷键]: 在 Normal 模式下按 <leader>r 或 <CR> 快速编译并运行该代码片段！',
      'package main',
      '',
      'import (',
      '    "fmt"',
      '    "math"',
      '    "strings"',
      ')',
      '',
      'func main() {',
      '    // 在此编写 Go 临时验证代码',
      '    ',
      '}'
    }
    return file_path, template, 12
  elseif filetype == 'rust' then
    local file_path = vim.fs.joinpath(dir, 'scratchpad.rs')
    local template = {
      '// [快捷键]: 在 Normal 模式下按 <leader>r 或 <CR> 快速编译并运行该代码片段！',
      'fn main() {',
      '    // 在此编写 Rust 临时验证代码',
      '    ',
      '}'
    }
    return file_path, template, 4
  end

  return nil, nil, nil
end

local function ensure_scratch_file(path, template)
  local stat = uv.fs_stat(path)
  if stat then
    return stat.type == 'file'
  end

  vim.fn.writefile(template, path)
  return true
end

-- 编译并运行临时验证代码
local function run_scratchpad(bufnr, file_path, filetype)
  -- 保存文件
  vim.cmd('w')

  local function do_run(cmd)
    if cmd == '' then
      vim.notify('不支持的语言类型', vim.log.levels.ERROR)
      return
    end

    vim.notify("正在编译运行代码片段...", vim.log.levels.INFO)
    local output = vim.fn.system(cmd)

    -- 追加注释形式的运行结果
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local clean_lines = strip_output_block(lines)
    trim_trailing_blank_lines(clean_lines)

    table.insert(clean_lines, '')
    table.insert(clean_lines, '/*')
    table.insert(clean_lines, OUTPUT_START_MARKER)
    for _, ol in ipairs(vim.split(output, '\n', { plain = true })) do
      table.insert(clean_lines, sanitize_output_line(ol))
    end
    table.insert(clean_lines, OUTPUT_END_MARKER)
    table.insert(clean_lines, '*/')

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, clean_lines)
    vim.cmd('w')
    vim.notify("运行成功，输出已以注释形式追加在底部", vim.log.levels.INFO)
  end

  local cmd = ''
  if filetype == 'java' then
    local project = require('user.project')
    local root = project.root(file_path)
    local function fallback_run()
      local cp_entries = {}
      if root and root ~= '' then
        local candidate_dirs = {
          vim.fs.joinpath(root, 'target', 'classes'),
          vim.fs.joinpath(root, 'target', 'test-classes'),
          vim.fs.joinpath(root, 'build', 'classes', 'java', 'main'),
          vim.fs.joinpath(root, 'build', 'classes', 'java', 'test'),
        }
        for _, d in ipairs(candidate_dirs) do
          local stat = uv.fs_stat(d)
          if stat and stat.type == 'directory' then
            table.insert(cp_entries, d)
          end
        end
      end
      local cp_arg = ''
      if #cp_entries > 0 then
        cp_arg = ' -cp ' .. vim.fn.shellescape(table.concat(cp_entries, ':') .. ':.')
      end
      do_run('java' .. cp_arg .. ' ' .. vim.fn.shellescape(file_path))
    end

    local client = find_jdtls_client(file_path)
    if not client then
      fallback_run()
      return
    end

    local success = pcall(function()
      get_java_classpath(client, bufnr, file_path, function(cp_entries)
        if not cp_entries then
          fallback_run()
          return
        end

        local cp_arg = ' -cp ' .. vim.fn.shellescape(table.concat(cp_entries, ':') .. ':.')
        do_run('java' .. cp_arg .. ' ' .. vim.fn.shellescape(file_path))
      end)
    end)
    if not success then
      fallback_run()
    end
    return
  elseif filetype == 'cpp' then
    local bin = file_path:gsub('%.cpp$', '_bin')
    cmd = 'g++ -std=c++17 ' .. vim.fn.shellescape(file_path) .. ' -o ' .. vim.fn.shellescape(bin) .. ' && ' .. vim.fn.shellescape(bin)
  elseif filetype == 'go' then
    cmd = 'go run ' .. vim.fn.shellescape(file_path)
  elseif filetype == 'rust' then
    local bin = file_path:gsub('%.rs$', '_bin')
    cmd = 'rustc ' .. vim.fn.shellescape(file_path) .. ' -o ' .. vim.fn.shellescape(bin) .. ' && ' .. vim.fn.shellescape(bin)
  end

  do_run(cmd)
end

-- 创建 Scratchpad
function M.open_scratchpad()
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.bo[bufnr].filetype

  -- 只支持 C++, Java, Go, Rust 三种语言
  local supported = { java = true, cpp = true, go = true, rust = true }
  if not supported[filetype] then
    -- 如果在其他 buffer (如 xml/dirvish)，尝试识别项目类型
    if is_file(vim.fs.joinpath(vim.fn.getcwd(), 'pom.xml')) or is_file(vim.fs.joinpath(vim.fn.getcwd(), 'build.gradle')) then
      filetype = 'java'
    elseif is_file(vim.fs.joinpath(vim.fn.getcwd(), 'go.mod')) then
      filetype = 'go'
    elseif is_file(vim.fs.joinpath(vim.fn.getcwd(), 'Cargo.toml')) then
      filetype = 'rust'
    else
      filetype = 'java' -- 默认 java
    end
  end

  local scratch_path, template, cursor_row = get_scratch_template(bufnr, file_path, filetype)
  if not scratch_path then
    vim.notify('无法创建临时文件模板', vim.log.levels.ERROR)
    return
  end

  if not ensure_scratch_file(scratch_path, template) then
    vim.notify('Scratchpad 路径已存在但不是普通文件', vim.log.levels.ERROR)
    return
  end

  -- 创建新 buffer 并加载临时文件
  local scratch_buf = vim.fn.bufadd(scratch_path)
  vim.fn.bufload(scratch_buf)
  vim.bo[scratch_buf].bufhidden = 'wipe'

  -- 打开美观的 rounded border 悬浮窗
  local win_opts = {
    relative = 'editor',
    width = math.floor(vim.o.columns * 0.7),
    height = math.floor(vim.o.lines * 0.6),
    col = math.floor(vim.o.columns * 0.15),
    row = math.floor(vim.o.lines * 0.15),
    style = 'minimal',
    border = 'rounded',
    title = ' 💡 Scratchpad (Normal Mode: <leader>r 或 <CR> 快速运行) ',
    title_pos = 'center',
  }

  local winid = vim.api.nvim_open_win(scratch_buf, true, win_opts)

  -- 设置光标默认在 main 函数内部
  vim.api.nvim_win_set_cursor(winid, { cursor_row, 8 })

  -- 配置快捷键以快速运行和关闭
  local map_opts = { buffer = scratch_buf, silent = true }
  vim.keymap.set('n', '<leader>r', function()
    run_scratchpad(scratch_buf, scratch_path, filetype)
  end, vim.tbl_extend('force', map_opts, { desc = 'Scratchpad: 运行验证代码' }))

  vim.keymap.set('n', '<CR>', function()
    run_scratchpad(scratch_buf, scratch_path, filetype)
  end, vim.tbl_extend('force', map_opts, { desc = 'Scratchpad: 运行验证代码' }))

  vim.keymap.set('n', 'q', function()
    vim.api.nvim_win_close(winid, true)
  end, vim.tbl_extend('force', map_opts, { desc = 'Scratchpad: 关闭窗口' }))

  vim.keymap.set('n', '<ESC>', function()
    vim.api.nvim_win_close(winid, true)
  end, vim.tbl_extend('force', map_opts, { desc = 'Scratchpad: 关闭窗口' }))

  -- 关闭时自动清理临时生成的可执行文件
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = scratch_buf,
    once = true,
    callback = function()
      if filetype == 'cpp' then
        local bin = scratch_path:gsub('%.cpp$', '_bin')
        pcall(os.remove, bin)
      elseif filetype == 'rust' then
        local bin = scratch_path:gsub('%.rs$', '_bin')
        pcall(os.remove, bin)
      end
    end
  })
end

M._test_run = run_scratchpad

vim.api.nvim_create_user_command('Scratchpad', function()
  M.open_scratchpad()
end, { desc = 'Open floating scratchpad window for quick code verification' })

return M
