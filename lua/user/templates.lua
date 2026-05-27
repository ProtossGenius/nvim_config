local M = {}

local function get_author()
  if vim.g.file_author and vim.g.file_author ~= "" then
    return vim.g.file_author
  end
  local git_name = vim.fn.system("git config user.name")
  git_name = vim.trim(git_name)
  if git_name ~= "" and vim.v.shell_error == 0 then
    return git_name
  end
  local user = os.getenv("USER") or os.getenv("USERNAME") or "Unknown"
  return user
end

local function get_date()
  return os.date("%Y-%m-%d %H:%M:%S")
end

local function get_java_package(filepath)
  filepath = filepath:gsub("\\", "/")
  local patterns = {
    "/src/main/java/",
    "/src/test/java/",
    "/src/main/kotlin/",
    "/src/test/kotlin/",
    "/src/",
    "/java/",
  }
  for _, pattern in ipairs(patterns) do
    local s, e = filepath:find(pattern, 1, true)
    if s then
      local suffix = filepath:sub(e + 1)
      local dir = vim.fn.fnamemodify(suffix, ":h")
      if dir ~= "." then
        return dir:gsub("/", ".")
      end
    end
  end
  return nil
end

function M.generate_template()
  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == "" then return end
  local ext = vim.fn.fnamemodify(filepath, ":e")
  local classname = vim.fn.fnamemodify(filepath, ":t:r")
  local author = get_author()
  local date = get_date()

  local lines = {}

  if ext == "java" then
    table.insert(lines, "/**")
    table.insert(lines, " * @author " .. author)
    table.insert(lines, " * @date " .. date)
    table.insert(lines, " */")
    local pkg = get_java_package(filepath)
    if pkg then
      table.insert(lines, "package " .. pkg .. ";")
      table.insert(lines, "")
    end
    table.insert(lines, "public class " .. classname .. " {")
    table.insert(lines, "")
    table.insert(lines, "}")
  elseif ext == "go" then
    table.insert(lines, "// @author " .. author)
    table.insert(lines, "// @date " .. date)
    table.insert(lines, "")
    local dir_name = vim.fn.fnamemodify(filepath, ":h:t")
    local pkg = (dir_name == "." or dir_name == "") and "main" or dir_name
    table.insert(lines, "package " .. pkg)
    table.insert(lines, "")
    if pkg == "main" then
      table.insert(lines, 'import "fmt"')
      table.insert(lines, "")
      table.insert(lines, "func main() {")
      table.insert(lines, '    fmt.Println("Hello, World!")')
      table.insert(lines, "}")
    end
  elseif ext == "py" then
    table.insert(lines, "# -*- coding: utf-8 -*-")
    table.insert(lines, "# @author " .. author)
    table.insert(lines, "# @date " .. date)
    table.insert(lines, "")
    table.insert(lines, "def main():")
    table.insert(lines, "    pass")
    table.insert(lines, "")
    table.insert(lines, 'if __name__ == "__main__":')
    table.insert(lines, "    main()")
  elseif ext == "rs" then
    table.insert(lines, "// @author " .. author)
    table.insert(lines, "// @date " .. date)
    table.insert(lines, "")
    table.insert(lines, "fn main() {")
    table.insert(lines, '    println!("Hello, World!");')
    table.insert(lines, "}")
  elseif ext == "sh" then
    table.insert(lines, "#!/bin/bash")
    table.insert(lines, "# @author " .. author)
    table.insert(lines, "# @date " .. date)
    table.insert(lines, "")
  elseif ext == "c" then
    table.insert(lines, "/**")
    table.insert(lines, " * @author " .. author)
    table.insert(lines, " * @date " .. date)
    table.insert(lines, " */")
    table.insert(lines, "")
    table.insert(lines, "#include <stdio.h>")
    table.insert(lines, "")
    table.insert(lines, "int main(int argc, char *argv[]) {")
    table.insert(lines, '    printf("Hello, World!\\n");')
    table.insert(lines, "    return 0;")
    table.insert(lines, "}")
  elseif ext == "cpp" or ext == "cc" or ext == "cxx" then
    table.insert(lines, "/**")
    table.insert(lines, " * @author " .. author)
    table.insert(lines, " * @date " .. date)
    table.insert(lines, " */")
    table.insert(lines, "")
    table.insert(lines, "#include <iostream>")
    table.insert(lines, "")
    table.insert(lines, "int main(int argc, char *argv[]) {")
    table.insert(lines, '    std::cout << "Hello, World!" << std::endl;')
    table.insert(lines, "    return 0;")
    table.insert(lines, "}")
  elseif ext == "js" or ext == "ts" or ext == "jsx" or ext == "tsx" then
    table.insert(lines, "/**")
    table.insert(lines, " * @author " .. author)
    table.insert(lines, " * @date " .. date)
    table.insert(lines, " */")
    table.insert(lines, "")
  elseif ext == "html" then
    table.insert(lines, "<!--")
    table.insert(lines, "  @author " .. author)
    table.insert(lines, "  @date " .. date)
    table.insert(lines, "-->")
    table.insert(lines, "<!DOCTYPE html>")
    table.insert(lines, '<html lang="en">')
    table.insert(lines, "<head>")
    table.insert(lines, '    <meta charset="UTF-8">')
    table.insert(lines, "    <title>Title</title>")
    table.insert(lines, "</head>")
    table.insert(lines, "<body>")
    table.insert(lines, "")
    table.insert(lines, "</body>")
    table.insert(lines, "</html>")
  end

  if #lines > 0 then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    if ext == "java" then
      vim.api.nvim_win_set_cursor(0, { #lines - 1, 0 })
    elseif ext == "go" and pkg == "main" then
      vim.api.nvim_win_set_cursor(0, { #lines - 1, 4 })
    elseif ext == "py" then
      vim.api.nvim_win_set_cursor(0, { 5, 8 })
    elseif ext == "rs" or ext == "c" or ext == "cpp" then
      vim.api.nvim_win_set_cursor(0, { #lines - 2, 4 })
    end
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("UserFileTemplates", { clear = true })
  vim.api.nvim_create_autocmd("BufNewFile", {
    group = group,
    pattern = "*",
    callback = function()
      M.generate_template()
    end,
  })
end

return M
