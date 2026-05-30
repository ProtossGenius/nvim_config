local M = {}

local uv = vim.uv or vim.loop
local output_buf = nil
local output_win = nil

local function is_file(path)
  local stat = path and path ~= '' and uv.fs_stat(path) or nil
  return stat and stat.type == 'file' or false
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

-- 编译并运行临时验证代码
local function run_scratchpad(bufnr, file_path, filetype)
  -- 保存文件
  vim.cmd('w')

  local cmd = ''
  if filetype == 'java' then
    cmd = 'java ' .. vim.fn.shellescape(file_path)
  elseif filetype == 'cpp' then
    local bin = file_path:gsub('%.cpp$', '_bin')
    cmd = 'g++ -std=c++17 ' .. vim.fn.shellescape(file_path) .. ' -o ' .. vim.fn.shellescape(bin) .. ' && ' .. vim.fn.shellescape(bin)
  elseif filetype == 'go' then
    cmd = 'go run ' .. vim.fn.shellescape(file_path)
  elseif filetype == 'rust' then
    local bin = file_path:gsub('%.rs$', '_bin')
    cmd = 'rustc ' .. vim.fn.shellescape(file_path) .. ' -o ' .. vim.fn.shellescape(bin) .. ' && ' .. vim.fn.shellescape(bin)
  end

  if cmd == '' then
    vim.notify('不支持的语言类型', vim.log.levels.ERROR)
    return
  end

  vim.notify("正在编译运行代码片段...", vim.log.levels.INFO)
  local output = vim.fn.system(cmd)

  -- 追加注释形式的运行结果
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local clean_lines = {}
  local skipping = false
  for _, line in ipairs(lines) do
    if line:match('^/%*%*%*%*%* result %*%*%*%*') then
      skipping = true
    end
    if not skipping then
      table.insert(clean_lines, line)
    end
    if line:match('^%*%*+ output end %*+') then
      skipping = false
    end
  end

  -- 去除末尾空行
  while #clean_lines > 0 and clean_lines[#clean_lines] == '' do
    table.remove(clean_lines)
  end

  table.insert(clean_lines, '')
  table.insert(clean_lines, "/***** result ****")
  for _, ol in ipairs(vim.split(output, '\n', { plain = true })) do
    table.insert(clean_lines, ol)
  end
  table.insert(clean_lines, "******** output end ******/")

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, clean_lines)
  vim.cmd('w')
  vim.notify("运行成功，输出已以注释形式追加在底部", vim.log.levels.INFO)
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

  -- 写入文件以使 LSP 能够探测到并附加
  vim.fn.writefile(template, scratch_path)

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

  -- 关闭时自动清理临时文件
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = scratch_buf,
    once = true,
    callback = function()
      pcall(os.remove, scratch_path)
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

return M
