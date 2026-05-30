local M = {}
local uv = vim.uv or vim.loop
local project = require('user.project')

-- 已知的基本类型/包装类型，不需要展开字段
local PRIMITIVE_TYPES = {
  String = true, Integer = true, Long = true, Double = true, Float = true,
  Boolean = true, Short = true, Byte = true, Character = true,
  BigDecimal = true, BigInteger = true, Date = true,
  LocalDate = true, LocalDateTime = true,
  int = true, long = true, double = true, float = true,
  boolean = true, short = true, byte = true, char = true,
  -- 常见集合/Map类型也视为基本类型
  List = true, Set = true, Map = true, Collection = true,
  Object = true, Void = true,
}

--- 属性名白名单：这些属性的值被视为类引用（FQN）
local CLASS_REF_ATTRS = {
  type = true,
  resulttype = true,
  parametertype = true,
  oftype = true,
  javatype = true,
  typehandler = true,
}

-- 读取文件内容为行数组
local function read_file_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return {}
  end
  return lines
end

local function is_file(path)
  local stat = path and path ~= '' and uv.fs_stat(path) or nil
  return stat and stat.type == 'file' or false
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 从当前 buffer 获取 mapper namespace
---@param bufnr number
---@return string|nil
local function get_namespace(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, line in ipairs(lines) do
    local ns = line:match('<mapper.-namespace%s*=%s*"([^"]+)"')
    if ns then
      return ns
    end
  end
end

--- 检查当前 buffer 是否是 mybatis mapper xml
---@param bufnr number
---@return boolean
local function is_mybatis_mapper(bufnr)
  if vim.bo[bufnr].filetype ~= 'xml' then
    return false
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local check_lines = math.min(line_count, 30)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, check_lines, false)
  for _, line in ipairs(lines) do
    -- DOCTYPE mapper 或 <mapper namespace="..."
    if line:match('<!DOCTYPE%s+mapper') or line:match('<mapper.-namespace') then
      return true
    end
  end
  return false
end

--- 将 FQN 转为相对文件路径: com.example.User -> com/example/User.java
---@param fqn string
---@return string
local function fqn_to_path(fqn)
  return fqn:gsub('%.', '/') .. '.java'
end

--- 获取光标所在行的属性值（type="...", resultType="...", parameterType="..." 等）
--- 返回属性名和属性值
---@param line string
---@param col number 光标列号(0-indexed)
---@return string|nil attr_name, string|nil attr_value
local function get_attribute_at_cursor(line, col)
  local start_pos = 1
  while true do
    local attr_start, attr_end, attr_name, _, attr_value = line:find('([%w_]+)%s*=%s*(["\'])(.-)%2', start_pos)
    if not attr_start then
      break
    end
    local val_start = attr_start - 1
    local val_end = attr_end - 1
    if col >= val_start and col <= val_end then
      return attr_name, attr_value
    end
    start_pos = attr_end + 1
  end
end

--- 在 project root 下搜索 Java 文件 (FQN -> file path)
---@param fqn string 完全限定类名
---@param bufnr number|nil
---@return string|nil path
local function find_java_file_by_fqn(fqn, bufnr)
  local root = project.root(bufnr)
  local rel_path = fqn_to_path(fqn)

  -- 优先在 src/main/java 和 src/test/java 下精确查找
  for _, java_root in ipairs({ 'src/main/java', 'src/test/java' }) do
    local exact = vim.fs.joinpath(root, java_root, rel_path)
    if is_file(exact) then
      return exact
    end
  end

  -- fallback: 用 project.find_exact_file 按 basename 查找
  local basename = fqn:match('[^%.]+$') .. '.java'
  local found, err = project.find_exact_file(basename, { root = root })
  if found then
    return found
  end

  -- find_exact_file 返回多个匹配时也会返回 nil，此时手动搜索
  if err and err:match('multiple') then
    local matches = vim.fs.find(function(name)
      return name == basename
    end, { path = root, type = 'file', limit = 20 })
    -- 尝试匹配包含 FQN 路径片段的结果
    local fqn_path_fragment = fqn:gsub('%.', '/')
    for _, match in ipairs(matches) do
      if match:find(fqn_path_fragment, 1, true) then
        return match
      end
    end
    -- 返回第一个
    return matches[1]
  end
end

--- 打开文件并跳转到指定行
---@param path string
---@param line_nr number|nil
---@param cmd string|nil
local function open_at(path, line_nr, cmd)
  vim.cmd((cmd or 'edit') .. ' ' .. vim.fn.fnameescape(path))
  vim.api.nvim_win_set_cursor(0, { math.max(line_nr or 1, 1), 0 })
  vim.cmd('normal! zz')
end

-- ============================================================================
-- 补全辅助函数
-- ============================================================================

local class_cache = {}
local cache_time = 0

local function get_all_project_classes(bufnr)
  local now = uv.now()
  if #class_cache > 0 and (now - cache_time) < 10000 then
    return class_cache
  end

  local root = project.root(bufnr)
  if not root or root == '' then
    return {}
  end

  local java_files = vim.fn.globpath(root, "/**/*.java", false, true)
  local classes = {}
  for _, file_path in ipairs(java_files) do
    local rel = file_path:match('src/[^/]+/java/(.+)%.java$')
    if not rel then
      rel = file_path:match('src/(.+)%.java$')
    end
    if rel then
      local fqn = rel:gsub('/', '.')
      table.insert(classes, fqn)
    end
  end

  class_cache = classes
  cache_time = now
  return classes
end

local function find_attribute_start(line, col)
  local start_pos = 1
  while true do
    local attr_start, attr_end, attr_name, _, attr_value = line:find('([%w_]+)%s*=%s*(["\'])(.-)%2', start_pos)
    if not attr_start then
      break
    end
    local quote_start = line:find('["\']', attr_start)
    if quote_start then
      local quote_start_col = quote_start
      local quote_end_col = attr_end - 1
      if col >= quote_start_col and col <= quote_end_col then
        return attr_name:lower(), quote_start_col
      end
    end
    start_pos = attr_end + 1
  end
  return nil, nil
end

local function get_completion_context(line, col)
  local left_str = line:sub(1, col)
  local param_start = left_str:match('.*[#$]{()([^}]*)$')
  if param_start then
    return 'parameter', param_start - 1
  end

  local attr_name, start_col = find_attribute_start(line, col)
  if attr_name then
    if CLASS_REF_ATTRS[attr_name] then
      return 'class', start_col
    elseif attr_name == 'resultmap' then
      return 'resultmap', start_col
    elseif attr_name == 'refid' then
      return 'refid', start_col
    end
  end

  return nil, nil
end

-- ============================================================================
-- 1. 类引用跳转 (Ctrl+])
-- ============================================================================

--- 尝试从光标位置跳转到类引用
---@param bufnr number
---@return boolean jumped 是否成功跳转
local function try_jump_class_ref(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line then
    return false
  end

  local attr_name, attr_value = get_attribute_at_cursor(line, cursor[2])
  if not attr_name or not attr_value then
    return false
  end

  -- 检查属性名是否是类引用类型（不区分大小写）
  if not CLASS_REF_ATTRS[attr_name:lower()] then
    return false
  end

  if attr_value == '' then
    return false
  end

  local java_path = find_java_file_by_fqn(attr_value, bufnr)
  if java_path then
    open_at(java_path, 1, 'edit')
    return true
  end

  vim.notify('找不到类文件: ' .. attr_value, vim.log.levels.WARN)
  return true  -- 已识别为类引用，但未找到文件
end

-- ============================================================================
-- 2. resultMap 引用跳转
-- ============================================================================

--- 尝试跳转到 resultMap 定义
---@param bufnr number
---@return boolean
local function try_jump_result_map(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line then
    return false
  end

  local attr_name, attr_value = get_attribute_at_cursor(line, cursor[2])
  if not attr_name or attr_name:lower() ~= 'resultmap' or not attr_value or attr_value == '' then
    return false
  end

  -- 在当前 buffer 中查找 <resultMap ... id="VALUE"
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local escaped = vim.pesc(attr_value)
  for i, l in ipairs(lines) do
    if l:match('<resultMap') and l:match('id%s*=%s*"' .. escaped .. '"') then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      vim.cmd('normal! zz')
      return true
    end
  end

  vim.notify('找不到 resultMap 定义: ' .. attr_value, vim.log.levels.WARN)
  return true
end

-- ============================================================================
-- 3. sql id / refid 引用跳转
-- ============================================================================

--- 尝试跳转到 sql id 定义 (通过 refid)
---@param bufnr number
---@return boolean
local function try_jump_refid(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line then
    return false
  end

  local attr_name, attr_value = get_attribute_at_cursor(line, cursor[2])
  if attr_name ~= 'refid' or not attr_value or attr_value == '' then
    return false
  end

  -- 在当前 buffer 中查找 <sql ... id="VALUE"
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local escaped = vim.pesc(attr_value)
  for i, l in ipairs(lines) do
    if l:match('<sql') and l:match('id%s*=%s*"' .. escaped .. '"') then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      vim.cmd('normal! zz')
      return true
    end
  end

  vim.notify('找不到 sql 定义: ' .. attr_value, vim.log.levels.WARN)
  return true
end

-- ============================================================================
-- 5. Ctrl+] 统一跳转处理 (已移动至参数解析函数下方)
-- ============================================================================

-- ============================================================================
-- 4. #{} / ${} 参数补全
-- ============================================================================

--- 向上搜索当前光标所在的 SQL 语句块，获取 statement id
---@param bufnr number
---@return string|nil statement_id
local function find_current_statement_id(bufnr)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local statement_tags = {
    select = true,
    insert = true,
    update = true,
    delete = true,
  }

  for start_line = cursor_line, 1, -1 do
    local tag_name = lines[start_line]:match('<(%w+)')
    if tag_name and statement_tags[tag_name] then
      -- 可能跨行，拼接直到找到 >
      local tag_text = lines[start_line]
      local end_line = start_line
      while end_line < #lines and not tag_text:find('>', 1, true) do
        end_line = end_line + 1
        tag_text = tag_text .. '\n' .. lines[end_line]
      end
      local statement_id = tag_text:match('id%s*=%s*"([^"]+)"')
      if statement_id then
        return statement_id
      end
    end
  end
end

--- 从 mapper.java 中找到对应方法的参数列表
--- 返回 { {name=..., type=..., param_annotation=...}, ... }
---@param java_path string
---@param method_name string
---@return table[]|nil
local function parse_method_params(java_path, method_name)
  local lines = read_file_lines(java_path)
  if #lines == 0 then
    return nil
  end

  -- 找到方法声明：先找方法名，然后提取参数列表
  local escaped_name = vim.pesc(method_name)
  local full_text = table.concat(lines, '\n')

  -- 匹配方法声明: returnType methodName(params)
  -- 支持泛型返回值和注解
  local pattern = '%f[%w_]' .. escaped_name .. '%s*%(([%s%S]-)%)%s*;'
  local params_str = full_text:match(pattern)
  if not params_str then
    return nil
  end

  local params = {}
  -- 分割参数（按逗号分隔，但要注意泛型中的逗号）
  -- 简化处理：先移除泛型尖括号内的内容
  local simplified = params_str:gsub('<[^>]*>', '')
  for part in simplified:gmatch('[^,]+') do
    part = vim.trim(part)
    if part ~= '' then
      -- 解析 @Param("name") Type paramName
      -- 或者 Type paramName
      local param_annotation = part:match('@Param%s*%(%s*"([^"]+)"%s*%)')
      -- 移除所有注解
      local no_annotations = part:gsub('@%w+%s*%([^)]*%)', ''):gsub('@%w+', '')
      no_annotations = vim.trim(no_annotations)
      -- 现在应该是 "Type name" 或 "Type... name"
      local type_name, param_name = no_annotations:match('^(.-)%s+([%w_]+)$')
      if type_name and param_name then
        -- 清理 type_name（移除 final 等修饰符）
        type_name = type_name:gsub('^final%s+', '')
        type_name = type_name:gsub('%.%.%.', '')  -- varargs
        type_name = vim.trim(type_name)
        -- 取简单类名（去掉包名）
        local simple_type = type_name:match('[^%.]+$') or type_name
        table.insert(params, {
          name = param_name,
          type = simple_type,
          full_type = type_name,
          param_annotation = param_annotation,
        })
      end
    end
  end

  return params
end

--- 从 Model 类文件中提取字段名列表
---@param model_path string
---@return string[]
local function extract_model_fields(model_path)
  local lines = read_file_lines(model_path)
  local fields = {}
  local in_class = false

  for _, line in ipairs(lines) do
    -- 检测到 class 声明开始
    if line:match('class%s+') then
      in_class = true
    end

    if in_class then
      -- 匹配字段声明: private/protected/public Type fieldName;
      -- 也匹配无修饰符的情况
      local trimmed = vim.trim(line)
      -- 跳过注解行
      if not trimmed:match('^@') and not trimmed:match('^//') and not trimmed:match('^/%*') and not trimmed:match('^%*') then
        -- 匹配: [modifier] Type fieldName [= ...];
        local field = trimmed:match('^%s*[%w%s<>,%.%[%]]*%s+([%w_]+)%s*[;=]')
        if field then
          -- 排除方法声明（含有括号）和类声明
          if not trimmed:match('%(') and not trimmed:match('^class%s')
            and not trimmed:match('^interface%s') and not trimmed:match('^enum%s')
            and not trimmed:match('^return%s') and not trimmed:match('^import%s')
            and not trimmed:match('^package%s')
            and field ~= 'serialVersionUID' then
            table.insert(fields, field)
          end
        end
      end
    end
  end

  -- 去重
  local seen = {}
  local unique = {}
  for _, f in ipairs(fields) do
    if not seen[f] then
      seen[f] = true
      table.insert(unique, f)
    end
  end

  return unique
end

local function get_lsp_symbols(file_path)
  local uri = vim.uri_from_fname(file_path)
  local clients = vim.lsp.get_clients({ name = 'jdtls' })
  if #clients == 0 then
    return nil
  end
  local client = clients[1]
  local response, err = client.request_sync('textDocument/documentSymbol', {
    textDocument = { uri = uri }
  }, 1000)
  if not response or response.err or not response.result then
    return nil
  end
  return response.result
end

local function extract_fields_from_symbols(symbols)
  local fields = {}
  local function traverse(syms)
    for _, sym in ipairs(syms) do
      if sym.kind == 8 or sym.kind == 7 then
        table.insert(fields, sym.name)
      end
      if sym.children and #sym.children > 0 then
        traverse(sym.children)
      end
    end
  end
  traverse(symbols)
  return fields
end

local function extract_model_fields_with_lsp(model_path)
  local symbols = get_lsp_symbols(model_path)
  if symbols and #symbols > 0 then
    local fields = extract_fields_from_symbols(symbols)
    if #fields > 0 then
      local filtered = {}
      for _, f in ipairs(fields) do
        if f ~= 'serialVersionUID' then
          table.insert(filtered, f)
        end
      end
      return filtered
    end
  end
  return extract_model_fields(model_path)
end

--- 判断类型是否是 Model（非基本类型，首字母大写）
---@param type_name string
---@return boolean
local function is_model_type(type_name)
  if not type_name or type_name == '' then
    return false
  end
  local simple = type_name:match('[^%.]+$') or type_name
  if PRIMITIVE_TYPES[simple] then
    return false
  end
  -- 首字母大写的非基本类型视为 Model
  return simple:match('^%u') ~= nil
end

--- 构建参数补全列表
---@param bufnr number
---@return string[]|nil items
local function build_param_items(bufnr)
  -- 1. 找到当前 statement id
  local statement_id = find_current_statement_id(bufnr)
  if not statement_id then
    vim.notify('未找到当前 SQL 语句块', vim.log.levels.WARN)
    return nil
  end

  -- 2. 找到对应的 mapper.java
  local namespace = get_namespace(bufnr)
  if not namespace then
    vim.notify('未找到 mapper namespace', vim.log.levels.WARN)
    return nil
  end

  local java_path = find_java_file_by_fqn(namespace, bufnr)
  if not java_path then
    vim.notify('找不到 Mapper.java: ' .. namespace, vim.log.levels.WARN)
    return nil
  end

  -- 3. 解析方法参数
  local params = parse_method_params(java_path, statement_id)
  if not params or #params == 0 then
    vim.notify('方法 ' .. statement_id .. ' 未找到参数', vim.log.levels.INFO)
    return nil
  end

  -- 4. 构建补全项
  local items = {}
  local single_param = (#params == 1)

  for _, param in ipairs(params) do
    -- 使用 @Param 注解名或参数名
    local display_name = param.param_annotation or param.name

    if is_model_type(param.type) then
      -- Model 类型：展开字段
      local model_path = find_java_file_by_fqn(param.full_type, bufnr)
      if not model_path and param.type ~= param.full_type then
        -- full_type 可能不是 FQN，尝试在同包下查找
        model_path = find_java_file_by_fqn(param.type, bufnr)
      end

      -- 尝试从 mapper.java 的 import 中推断 FQN
      if not model_path then
        local java_lines = read_file_lines(java_path)
        local simple_type = param.type:match('[^%.]+$') or param.type
        for _, jl in ipairs(java_lines) do
          local import_fqn = jl:match('^%s*import%s+([%w_%.]+)%s*;')
          if import_fqn then
            local import_simple = import_fqn:match('[^%.]+$')
            if import_simple == simple_type then
              model_path = find_java_file_by_fqn(import_fqn, bufnr)
              break
            end
          end
        end
      end

      if model_path then
        local fields = extract_model_fields_with_lsp(model_path)
        if #fields > 0 then
          for _, field in ipairs(fields) do
            if single_param then
              -- 唯一参数的 Model: 同时支持直接用字段名和 paramName.field
              table.insert(items, field)
              table.insert(items, display_name .. '.' .. field)
            else
              -- 多参数: 用 paramName.field
              table.insert(items, display_name .. '.' .. field)
            end
          end
        else
          -- 找不到字段，至少提供参数名
          table.insert(items, display_name)
        end
      else
        -- 找不到 Model 文件，直接用参数名
        table.insert(items, display_name)
      end
    else
      -- 基本类型: 直接使用参数名
      table.insert(items, display_name)
    end
  end

  return items
end

local function find_completion_start_col(line, cursor_col)
  -- 0-indexed cursor position backward search
  for c = cursor_col, 1, -1 do
    local char = line:sub(c, c)
    local prev_char = c > 1 and line:sub(c - 1, c - 1) or ''
    if char == '{' and (prev_char == '#' or prev_char == '$') then
      return c -- 1-indexed column of '{'
    end
  end
  return nil
end

local function trigger_autocomplete_inline(bufnr, ctx, start_col)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''

  local base = line:sub(start_col + 1, col)
  M._omnifunc_context = ctx
  local matches = M.omnifunc(0, base)
  if matches and #matches > 0 then
    vim.fn.complete(start_col + 1, matches)
  end
end

local function trigger_param_completion(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  local ctx, start_col = get_completion_context(line, col)
  if ctx and start_col then
    trigger_autocomplete_inline(bufnr, ctx, start_col)
  end
end

--- 手动触发参数补全
---@param bufnr number
local function manual_trigger(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''

  -- 检查光标左侧是否有未闭合的 #{ 或 ${，或者是否处于属性值内部
  local left_str = line:sub(1, col)
  local has_brace_left = left_str:match('#{[^}]*$') or left_str:match('%${[^}]*$')
  local ctx, _ = get_completion_context(line, col)

  if has_brace_left or ctx then
    trigger_param_completion(bufnr)
  else
    vim.notify('光标不在补全上下文内部', vim.log.levels.WARN)
  end
end

-- ============================================================================
-- 6. insert 模式 `{` 键覆盖
-- ============================================================================

--- 在 insert 模式下处理 `{` 输入
---@param bufnr number
local function handle_open_brace(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''

  local char_before = col > 0 and line:sub(col, col) or ''

  if char_before == '#' or char_before == '$' then
    vim.api.nvim_feedkeys('{', 'n', false)
    vim.schedule(function()
      trigger_param_completion(bufnr)
    end)
  else
    vim.api.nvim_feedkeys('{', 'n', false)
  end
end

-- ============================================================================
-- 7. Omnifunc 补全接口与自动触发
-- ============================================================================

function M.omnifunc(findstart, base)
  local bufnr = vim.api.nvim_get_current_buf()
  if findstart == 1 then
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local col = cursor[2]
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
    local ctx, start_col = get_completion_context(line, col)
    if start_col then
      M._omnifunc_context = ctx
      return start_col
    else
      return -1
    end
  else
    local ctx = M._omnifunc_context
    if not ctx then
      return {}
    end

    local matches = {}
    local base_lower = base:lower()

    if ctx == 'parameter' then
      local items = build_param_items(bufnr) or {}
      local cursor = vim.api.nvim_win_get_cursor(0)
      local row = cursor[1] - 1
      local col = cursor[2]
      local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
      local next_char = line:sub(col + 1, col + 1)
      local closing = (next_char == '}') and '' or '}'

      for _, item in ipairs(items) do
        if item:lower():find(base_lower, 1, true) == 1 then
          table.insert(matches, {
            word = item .. closing,
            abbr = item,
            menu = '[Param]',
          })
        end
      end
    elseif ctx == 'class' then
      local classes = get_all_project_classes(bufnr)
      for _, class in ipairs(classes) do
        if class:lower():find(base_lower, 1, true) then
          table.insert(matches, {
            word = class,
            abbr = class:match('[^%.]+$') or class,
            menu = '[Class]',
            info = class,
          })
        end
      end
    elseif ctx == 'resultmap' then
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for _, l in ipairs(lines) do
        local id = l:match('<resultMap.-id%s*=%s*"([^"]+)"') or l:match("<resultMap.-id%s*=%s*'([^']+)'")
        if id then
          if id:lower():find(base_lower, 1, true) == 1 then
            table.insert(matches, {
              word = id,
              abbr = id,
              menu = '[ResultMap]',
            })
          end
        end
      end
    elseif ctx == 'refid' then
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for _, l in ipairs(lines) do
        local id = l:match('<sql.-id%s*=%s*"([^"]+)"') or l:match("<sql.-id%s*=%s*'([^']+)'")
        if id then
          if id:lower():find(base_lower, 1, true) == 1 then
            table.insert(matches, {
              word = id,
              abbr = id,
              menu = '[SQL]',
            })
          end
        end
      end
    end

    return matches
  end
end

local function setup_autocomplete(bufnr)
  vim.bo[bufnr].omnifunc = 'v:lua.require("user.mybatis").omnifunc'

  local group = vim.api.nvim_create_augroup('UserMyBatisAutocomplete_' .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd({ 'TextChangedI', 'InsertCharPre' }, {
    group = group,
    buffer = bufnr,
    callback = function()
      if vim.fn.pumvisible() ~= 0 then
        return
      end
      if vim.api.nvim_get_mode().mode ~= 'i' then
        return
      end

      vim.schedule(function()
        if vim.api.nvim_get_mode().mode == 'i' and vim.fn.pumvisible() == 0 then
          local current_cursor = vim.api.nvim_win_get_cursor(0)
          local current_line = vim.api.nvim_buf_get_lines(bufnr, current_cursor[1] - 1, current_cursor[1], false)[1] or ''
          local current_ctx, current_start = get_completion_context(current_line, current_cursor[2])
          if current_ctx and current_start then
            trigger_autocomplete_inline(bufnr, current_ctx, current_start)
          end
        end
      end)
    end
  })
end

-- ============================================================================
-- resultMap property 跳转与占位符跳转辅助函数
-- ============================================================================

local function find_enclosing_resultmap_type(bufnr)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i = cursor_line, 1, -1 do
    local line = lines[i]
    if line:match('</resultMap>') then
      return nil
    end
    if line:match('<resultMap') then
      local model_type = line:match('type%s*=%s*"([^"]+)"') or line:match("type%s*=%s*'([^']+)'")
      if model_type then
        return model_type
      end
    end
  end
  return nil
end

local function find_field_declaration_line(lines, field_name)
  local pattern = '%s+([%w_%.<>,%[%]]+)%s+' .. vim.pesc(field_name) .. '%s*[;=]'
  for i, line in ipairs(lines) do
    if not line:match('^%s*//') and not line:match('^%s*@') then
      if line:match(pattern) then
        return i
      end
    end
  end
  for i, line in ipairs(lines) do
    if not line:match('^%s*//') and not line:match('^%s*@') then
      if line:find('%f[%w_]' .. vim.pesc(field_name) .. '%f[^%w_]') then
        return i
      end
    end
  end
  return 1
end

local function jump_to_model_field(model_fqn, field_name, bufnr)
  local java_path = find_java_file_by_fqn(model_fqn, bufnr)
  if not java_path then
    return false
  end

  local lines = read_file_lines(java_path)
  if #lines == 0 then
    return false
  end

  local line_nr = find_field_declaration_line(lines, field_name)
  open_at(java_path, line_nr, 'edit')
  return true
end

local function get_placeholder_at_cursor(line, col)
  local start_pos = 1
  while true do
    local p_start, p_end, content = line:find('[#$]%s*{%s*([^}]+)%s*}', start_pos)
    if not p_start then
      break
    end
    local val_start = p_start - 1
    local val_end = p_end - 1
    if col >= val_start and col <= val_end then
      return vim.trim(content)
    end
    start_pos = p_end + 1
  end
  return nil
end

local function resolve_param_type_fqn(param, java_path)
  if param.full_type:find('%.', 1, true) then
    return param.full_type
  end
  local lines = read_file_lines(java_path)
  local package = ''
  for _, l in ipairs(lines) do
    local pkg = l:match('^%s*package%s+([%w_%.]+)%s*;')
    if pkg then
      package = pkg
    end
    local imp = l:match('^%s*import%s+([%w_%.]+)%s*;')
    if imp then
      if imp:match('[^%.]+$') == param.type then
        return imp
      end
    end
  end
  if package ~= '' then
    return package .. '.' .. param.type
  end
  return param.type
end

local function resolve_type_fqn_in_file(type_name, file_path)
  local simple_type = type_name:gsub('<[^>]*>', '')
  simple_type = simple_type:match('[^%.]+$') or simple_type
  
  local lines = read_file_lines(file_path)
  local package = ''
  for _, l in ipairs(lines) do
    local pkg = l:match('^%s*package%s+([%w_%.]+)%s*;')
    if pkg then
      package = pkg
    end
    local imp = l:match('^%s*import%s+([%w_%.]+)%s*;')
    if imp then
      if imp:match('[^%.]+$') == simple_type then
        return imp
      end
    end
  end
  if package ~= '' then
    return package .. '.' .. simple_type
  end
  return simple_type
end

local function find_method_line(lines, method_name)
  local escaped = vim.pesc(method_name)
  for i, l in ipairs(lines) do
    if l:find('%f[%w_]' .. escaped .. '%f[^%w_]%s*%(') then
      return i
    end
  end
  return 1
end

-- ============================================================================
-- 4. resultMap property 跳转
-- ============================================================================

local function try_jump_resultmap_property(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line then
    return false
  end

  local property_val = line:match('property%s*=%s*"([^"]+)"') or line:match("property%s*=%s*'([^']+)'")
  if not property_val or property_val == '' then
    return false
  end

  local model_type = find_enclosing_resultmap_type(bufnr)
  if not model_type then
    return false
  end

  if jump_to_model_field(model_type, property_val, bufnr) then
    return true
  end

  return false
end

-- ============================================================================
-- 5. 占位符跳转
-- ============================================================================

local function try_jump_placeholder(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line then
    return false
  end

  local placeholder = get_placeholder_at_cursor(line, cursor[2])
  if not placeholder or placeholder == '' then
    return false
  end

  local parts = vim.split(placeholder, '.', { plain = true })
  if #parts == 0 then
    return false
  end

  local statement_id = find_current_statement_id(bufnr)
  if not statement_id then
    return false
  end

  local namespace = get_namespace(bufnr)
  if not namespace then
    return false
  end

  local java_path = find_java_file_by_fqn(namespace, bufnr)
  if not java_path then
    return false
  end

  local params = parse_method_params(java_path, statement_id)
  if not params or #params == 0 then
    return false
  end

  if #parts > 1 then
    -- 对应 #{user.name} 这种多级属性跳转
    for _, param in ipairs(params) do
      local display_name = param.param_annotation or param.name
      if display_name == parts[1] then
        local current_fqn = resolve_param_type_fqn(param, java_path)
        for idx = 2, #parts do
          local field = parts[idx]
          local m_path = find_java_file_by_fqn(current_fqn, bufnr)
          if not m_path then
            break
          end
          local m_lines = read_file_lines(m_path)
          local line_idx = find_field_declaration_line(m_lines, field)

          if idx == #parts then
            open_at(m_path, line_idx, 'edit')
            return true
          else
            local decl_line = m_lines[line_idx] or ''
            local type_name = decl_line:match('%s+([%w_%.<>,%[%]]+)%s+' .. vim.pesc(field) .. '%s*[;=]')
            if type_name then
              current_fqn = resolve_type_fqn_in_file(type_name, m_path)
            else
              break
            end
          end
        end
      end
    end
  else
    -- 对应 #{username} 这种单字段跳转
    -- 优先匹配 Mapper.java 的参数名
    for _, param in ipairs(params) do
      local display_name = param.param_annotation or param.name
      if display_name == parts[1] then
        local mapper_lines = read_file_lines(java_path)
        local method_line = find_method_line(mapper_lines, statement_id)
        open_at(java_path, method_line, 'edit')
        return true
      end
    end

    -- 其次如果只有一个 Model 参数，匹配 Model 的字段
    if #params == 1 and is_model_type(params[1].type) then
      local param = params[1]
      local current_fqn = resolve_param_type_fqn(param, java_path)
      if jump_to_model_field(current_fqn, parts[1], bufnr) then
        return true
      end
    end
  end

  return false
end

-- ============================================================================
-- 6. Ctrl+] 统一跳转处理 (已移动至参数解析函数下方)
-- ============================================================================

local function jump_handler(bufnr)
  -- 1) 类引用跳转
  if try_jump_class_ref(bufnr) then
    return
  end

  -- 2) resultMap 属性值跳转 (NEW)
  if try_jump_resultmap_property(bufnr) then
    return
  end

  -- 3) resultMap 引用跳转
  if try_jump_result_map(bufnr) then
    return
  end

  -- 4) refid 引用跳转
  if try_jump_refid(bufnr) then
    return
  end

  -- 5) 占位符跳转 (NEW)
  if try_jump_placeholder(bufnr) then
    return
  end

  -- 6) fallback: 跳转到对应的 mapper.java
  local ok, java = pcall(require, 'user.java')
  if ok and java.jump_mapper_pair then
    java.jump_mapper_pair('edit')
  end
end

-- ============================================================================
-- M.setup()
-- ============================================================================

function M.setup()
  local group = vim.api.nvim_create_augroup('UserMyBatis', { clear = true })

  vim.api.nvim_create_autocmd({ 'BufEnter', 'FileType' }, {
    group = group,
    pattern = { '*.xml' },
    callback = function(args)
      local bufnr = args.buf
      -- 延迟检查，确保 buffer 内容已加载
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end
        if not is_mybatis_mapper(bufnr) then
          return
        end

        local map_opts = { buffer = bufnr, silent = true }
        setup_autocomplete(bufnr)

        -- Ctrl+] 统一跳转
        vim.keymap.set('n', '<C-]>', function()
          jump_handler(bufnr)
        end, vim.tbl_extend('force', map_opts, { desc = 'MyBatis: 跳转引用' }))

        -- insert 模式 { 键覆盖
        vim.keymap.set('i', '{', function()
          handle_open_brace(bufnr)
        end, vim.tbl_extend('force', map_opts, { desc = 'MyBatis: 参数补全' }))

        -- 手动触发补全
        vim.api.nvim_buf_create_user_command(bufnr, 'MyBatisParamComplete', function()
          manual_trigger(bufnr)
        end, { desc = 'MyBatis: 手动参数补全' })

        vim.keymap.set('i', '<C-x><C-o>', function()
          manual_trigger(bufnr)
        end, vim.tbl_extend('force', map_opts, { desc = 'MyBatis: 手动参数补全' }))

        vim.keymap.set('n', '<leader>lp', function()
          manual_trigger(bufnr)
        end, vim.tbl_extend('force', map_opts, { desc = 'MyBatis: 手动参数补全' }))
      end)
    end,
  })
end

M._test = {
  parse_method_params = parse_method_params,
  extract_model_fields = extract_model_fields,
  is_model_type = is_model_type,
  get_attribute_at_cursor = get_attribute_at_cursor,
  get_namespace = get_namespace,
  is_mybatis_mapper = is_mybatis_mapper,
  fqn_to_path = fqn_to_path,
  find_java_file_by_fqn = find_java_file_by_fqn,
  find_current_statement_id = find_current_statement_id,
  build_param_items = build_param_items,
  get_all_project_classes = get_all_project_classes,
  get_completion_context = get_completion_context,
  find_enclosing_resultmap_type = find_enclosing_resultmap_type,
  find_field_declaration_line = find_field_declaration_line,
  get_placeholder_at_cursor = get_placeholder_at_cursor,
  resolve_param_type_fqn = resolve_param_type_fqn,
  resolve_type_fqn_in_file = resolve_type_fqn_in_file,
  try_jump_resultmap_property = try_jump_resultmap_property,
  try_jump_placeholder = try_jump_placeholder,
  extract_model_fields_with_lsp = extract_model_fields_with_lsp,
}

return M
