-- [[ user.datasource ]]
-- 数据库表结构同步模块
-- 自动比对 MySQL 表结构与 MyBatis resultMap / Java Model，补齐缺失字段

local M = {}
local project = require('user.project')
local uv = vim.uv or vim.loop

local CONFIG_FILENAME = '.nvim-datasource.json'

-- ╭──────────────────────────────────────────────────────────╮
-- │ Helpers                                                  │
-- ╰──────────────────────────────────────────────────────────╯

local function is_file(path)
  local stat = path and path ~= '' and uv.fs_stat(path) or nil
  return stat and stat.type == 'file' or false
end

local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return {}
  end
  return lines
end

local function read_file_text(path)
  local lines = read_file(path)
  return table.concat(lines, '\n')
end

local function write_file(path, text)
  local lines = vim.split(text, '\n', { plain = true })
  vim.fn.writefile(lines, path)
end

local function find_files_by_name(root, filename, limit)
  return vim.fs.find(function(name)
    return name == filename
  end, {
    path = root,
    type = 'file',
    limit = limit or 50,
  })
end

-- ╭──────────────────────────────────────────────────────────╮
-- │ 1. load_config                                           │
-- ╰──────────────────────────────────────────────────────────╯

--- 从项目根目录读取 .nvim-datasource.json 配置文件
---@return table|nil config 配置表，找不到文件时返回 nil
function M.load_config()
  local config_path = project.config_path(CONFIG_FILENAME)
  if not is_file(config_path) then
    vim.notify('[datasource] 找不到配置文件: ' .. CONFIG_FILENAME, vim.log.levels.WARN)
    return nil
  end

  local text = read_file_text(config_path)
  local ok, config = pcall(vim.json.decode, text)
  if not ok or type(config) ~= 'table' then
    vim.notify('[datasource] 配置文件解析失败: ' .. CONFIG_FILENAME, vim.log.levels.ERROR)
    return nil
  end

  return config
end

-- ╭──────────────────────────────────────────────────────────╮
-- │ 2. fetch_table_columns (异步)                             │
-- ╰──────────────────────────────────────────────────────────╯

--- 异步调用 Python 脚本获取表结构
---@param config table 数据源配置
---@param table_name string 表名
---@param callback fun(columns: table[]|nil, err: string|nil)
function M.fetch_table_columns(config, table_name, callback)
  local script = vim.fs.joinpath(vim.fn.stdpath('config'), 'scripts', 'fetch_table_schema.py')
  if not is_file(script) then
    callback(nil, 'Python 脚本不存在: ' .. script)
    return
  end

  local cmd = {
    'python3', script,
    '--host', config.host or 'localhost',
    '--port', tostring(config.port or 3306),
    '--user', config.user or 'root',
    '--password', config.password or '',
    '--database', config.database or '',
    '--table', table_name,
  }
  if config.skip_ssl then
    table.insert(cmd, '--skip-ssl')
  end

  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        -- 尝试解析 stderr / stdout 中的 JSON 错误
        local output = (result.stdout or '') .. (result.stderr or '')
        local ok, data = pcall(vim.json.decode, output)
        if ok and data and data.error then
          callback(nil, data.error)
        else
          callback(nil, '脚本执行失败 (code=' .. tostring(result.code) .. '): ' .. output)
        end
        return
      end

      local ok, data = pcall(vim.json.decode, result.stdout or '')
      if not ok or type(data) ~= 'table' then
        callback(nil, 'JSON 解析失败: ' .. (result.stdout or ''))
        return
      end

      if data.error then
        callback(nil, data.error)
        return
      end

      callback(data.columns or {}, nil)
    end)
  end)
end

-- ╭──────────────────────────────────────────────────────────╮
-- │ 3. find_table_name                                       │
-- ╰──────────────────────────────────────────────────────────╯

--- 从 Java 文件中解析注解获取表名
--- 支持 @ClassName(field = "value") 和 @ClassName("value") 两种格式
---@param java_file_path string Java 文件路径
---@param annotation_config table { class = "Table", field = "table" }
---@return string|nil table_name
function M.find_table_name(java_file_path, annotation_config)
  if not java_file_path or not is_file(java_file_path) then
    return nil
  end

  local lines = read_file(java_file_path)
  local class_name = annotation_config.class
  local field_name = annotation_config.field

  -- 将所有行拼成一个字符串方便跨行注解匹配
  local content = table.concat(lines, '\n')

  -- 模式1: @ClassName(field = "value")
  local pattern1 = '@' .. vim.pesc(class_name) .. '%s*%(' .. '.-' .. vim.pesc(field_name) .. '%s*=%s*"([^"]+)"'
  local value = content:match(pattern1)
  if value then
    return value
  end

  -- 模式2: @ClassName("value") — 单值简写
  local pattern2 = '@' .. vim.pesc(class_name) .. '%s*%(%s*"([^"]+)"%s*%)'
  value = content:match(pattern2)
  if value then
    return value
  end

  return nil
end

-- ╭──────────────────────────────────────────────────────────╮
-- │ 4. parse_resultmap                                       │
-- ╰──────────────────────────────────────────────────────────╯

--- 解析 mapper XML 中的 resultMap 块
---@param mapper_xml_path string mapper XML 文件路径
---@return table[] resultmap_entries { column, property, jdbc_type }
---@return table[] resultmap_metas  { id, type } — 每个 resultMap 的基本信息
function M.parse_resultmap(mapper_xml_path)
  local content = read_file_text(mapper_xml_path)
  local entries = {}
  local metas = {}

  -- 遍历每个 <resultMap ...>...</resultMap> 块
  for rm_tag, rm_body in content:gmatch('<resultMap([^>]-)>(.-)</resultMap>') do
    local rm_id = rm_tag:match('id%s*=%s*"([^"]+)"')
    local rm_type = rm_tag:match('type%s*=%s*"([^"]+)"')
    table.insert(metas, { id = rm_id, type = rm_type })

    -- 匹配 <result .../> 和 <id .../> 标签
    for tag_content in rm_body:gmatch('<[iI]?[dD]?[rR]?[eE]?[sS]?[uU]?[lL]?[tT]?%s([^>]-)/>') do
      -- 更精确地匹配 <result .../> 和 <id .../>
    end
    for tag_name, tag_content in rm_body:gmatch('<(%w+)%s([^>]-)/?>') do
      if tag_name == 'result' or tag_name == 'id' then
        local col = tag_content:match('column%s*=%s*"([^"]+)"')
        local prop = tag_content:match('property%s*=%s*"([^"]+)"')
        local jdbc = tag_content:match('jdbcType%s*=%s*"([^"]+)"')
        if col and prop then
          table.insert(entries, {
            column = col,
            property = prop,
            jdbc_type = jdbc or '',
          })
        end
      end
    end
  end

  return entries, metas
end

-- ╭──────────────────────────────────────────────────────────╮
-- │ 5. parse_model_fields                                    │
-- ╰──────────────────────────────────────────────────────────╯

--- 解析 Java Model 文件中的字段声明
---@param model_java_path string Model.java 文件路径
---@return table[] fields { name, type }
---@return boolean has_data 是否有 @Data 注解
function M.parse_model_fields(model_java_path)
  local lines = read_file(model_java_path)
  local fields = {}
  local has_data = false

  for _, line in ipairs(lines) do
    -- 检测 @Data 注解
    if line:match('@Data') then
      has_data = true
    end

    -- 匹配 private Type fieldName;
    -- 支持泛型如 List<String>，数组如 byte[]
    local field_type, field_name = line:match('^%s*private%s+([%w_<>%[%],%s%.]+)%s+([%w_]+)%s*[=;]')
    if field_type and field_name then
      -- 清理类型字符串中的多余空格
      field_type = field_type:gsub('%s+$', ''):gsub('%s+', ' ')
      table.insert(fields, { name = field_name, type = field_type })
    end
  end

  return fields, has_data
end

-- ╭──────────────────────────────────────────────────────────╮
-- │ 6. snake_to_camel                                        │
-- ╰──────────────────────────────────────────────────────────╯

--- 下划线命名转驼峰命名: user_name → userName
---@param name string
---@return string
function M.snake_to_camel(name)
  if not name or name == '' then
    return name or ''
  end
  -- 首先全部小写，再将 _x 转为 X
  local result = name:lower():gsub('_(%w)', function(c)
    return c:upper()
  end)
  return result
end

-- ╭──────────────────────────────────────────────────────────╮
-- │ 7. mysql_type_to_java                                    │
-- ╰──────────────────────────────────────────────────────────╯

local mysql_to_java_map = {
  bigint      = 'Long',
  int         = 'Integer',
  integer     = 'Integer',
  tinyint     = 'Integer',
  smallint    = 'Integer',
  mediumint   = 'Integer',
  varchar     = 'String',
  char        = 'String',
  text        = 'String',
  longtext    = 'String',
  mediumtext  = 'String',
  datetime    = 'Date',
  timestamp   = 'Date',
  date        = 'Date',
  decimal     = 'BigDecimal',
  numeric     = 'BigDecimal',
  double      = 'Double',
  float       = 'Float',
  bit         = 'Boolean',
  boolean     = 'Boolean',
  blob        = 'byte[]',
  longblob    = 'byte[]',
  mediumblob  = 'byte[]',
}

--- MySQL 类型转 Java 类型
---@param mysql_type string 如 "varchar(64)", "bigint"
---@return string java_type
function M.mysql_type_to_java(mysql_type)
  if not mysql_type then
    return 'Object'
  end
  -- 取基础类型名（去括号和参数）
  local base = mysql_type:lower():match('^(%w+)')
  return mysql_to_java_map[base] or 'Object'
end

-- ╭──────────────────────────────────────────────────────────╮
-- │ 8. mysql_type_to_jdbc                                    │
-- ╰──────────────────────────────────────────────────────────╯

local mysql_to_jdbc_map = {
  bigint    = 'BIGINT',
  int       = 'INTEGER',
  integer   = 'INTEGER',
  varchar   = 'VARCHAR',
  char      = 'VARCHAR',
  text      = 'LONGVARCHAR',
  longtext  = 'LONGVARCHAR',
  mediumtext = 'LONGVARCHAR',
  datetime  = 'TIMESTAMP',
  timestamp = 'TIMESTAMP',
  date      = 'DATE',
  decimal   = 'DECIMAL',
  numeric   = 'DECIMAL',
  double    = 'DOUBLE',
  float     = 'FLOAT',
  bit       = 'BIT',
  boolean   = 'BIT',
  tinyint   = 'TINYINT',
  smallint  = 'SMALLINT',
  mediumint = 'INTEGER',
  blob      = 'BLOB',
  longblob  = 'BLOB',
  mediumblob = 'BLOB',
}

--- MySQL 类型转 JDBC 类型
---@param mysql_type string
---@return string jdbc_type
function M.mysql_type_to_jdbc(mysql_type)
  if not mysql_type then
    return 'VARCHAR'
  end
  local base = mysql_type:lower():match('^(%w+)')
  return mysql_to_jdbc_map[base] or 'VARCHAR'
end

-- ╭──────────────────────────────────────────────────────────╮
-- │ 9. compute_diff                                          │
-- ╰──────────────────────────────────────────────────────────╯

--- 比对数据库列、resultMap 字段和 Model 字段的差异
---@param db_columns table[]  数据库列 { name, type, nullable, key }
---@param resultmap_fields table[] resultMap 字段 { column, property, jdbc_type }
---@param model_fields table[] Model 字段 { name, type }
---@return table diff { missing_in_resultmap, missing_in_model, type_mismatch_in_model }
function M.compute_diff(db_columns, resultmap_fields, model_fields)
  -- 构建已存在的 resultMap column 集合
  local rm_columns = {}
  for _, entry in ipairs(resultmap_fields) do
    rm_columns[entry.column] = true
  end

  -- 构建已存在的 model 字段映射 (property_name → type)
  local model_map = {}
  for _, field in ipairs(model_fields) do
    model_map[field.name] = field.type
  end

  local missing_in_resultmap = {}
  local missing_in_model = {}
  local type_mismatch_in_model = {}

  for _, col in ipairs(db_columns) do
    local property_name = M.snake_to_camel(col.name)
    local expected_java_type = M.mysql_type_to_java(col.type)
    local jdbc_type = M.mysql_type_to_jdbc(col.type)

    -- 检查是否在 resultMap 中
    if not rm_columns[col.name] then
      table.insert(missing_in_resultmap, {
        column = col.name,
        property = property_name,
        jdbc_type = jdbc_type,
        java_type = expected_java_type,
        mysql_type = col.type,
      })
    end

    -- 检查是否在 model 中
    local existing_type = model_map[property_name]
    if not existing_type then
      table.insert(missing_in_model, {
        name = property_name,
        java_type = expected_java_type,
        column = col.name,
        mysql_type = col.type,
      })
    elseif existing_type ~= expected_java_type then
      table.insert(type_mismatch_in_model, {
        name = property_name,
        expected = expected_java_type,
        actual = existing_type,
        column = col.name,
      })
    end
  end

  return {
    missing_in_resultmap = missing_in_resultmap,
    missing_in_model = missing_in_model,
    type_mismatch_in_model = type_mismatch_in_model,
  }
end

--- 判断 diff 是否为空
---@param diff table
---@return boolean
local function is_diff_empty(diff)
  return #diff.missing_in_resultmap == 0
    and #diff.missing_in_model == 0
    and #diff.type_mismatch_in_model == 0
end

-- ╭──────────────────────────────────────────────────────────╮
-- │ 浮窗展示 diff 摘要                                       │
-- ╰──────────────────────────────────────────────────────────╯

--- 在浮窗中展示 diff 摘要，用户确认后执行回调
---@param diff table
---@param context table { mapper_xml, model_java, table_name }
---@param on_confirm fun()
local function show_diff_window(diff, context, on_confirm)
  local lines = {}
  table.insert(lines, '表: ' .. (context.table_name or '?'))
  table.insert(lines, 'Mapper XML: ' .. (context.mapper_xml or '?'))
  table.insert(lines, 'Model Java: ' .. (context.model_java or '?'))
  table.insert(lines, string.rep('─', 60))

  if #diff.missing_in_resultmap > 0 then
    table.insert(lines, '')
    table.insert(lines, '▸ resultMap 中缺失的列 (' .. #diff.missing_in_resultmap .. '):')
    for _, entry in ipairs(diff.missing_in_resultmap) do
      table.insert(lines, '    <result column="' .. entry.column .. '" property="' .. entry.property .. '" jdbcType="' .. entry.jdbc_type .. '"/>')
    end
  end

  if #diff.missing_in_model > 0 then
    table.insert(lines, '')
    table.insert(lines, '▸ Model 中缺失的字段 (' .. #diff.missing_in_model .. '):')
    for _, entry in ipairs(diff.missing_in_model) do
      table.insert(lines, '    private ' .. entry.java_type .. ' ' .. entry.name .. ';  ← ' .. entry.column .. ' (' .. entry.mysql_type .. ')')
    end
  end

  if #diff.type_mismatch_in_model > 0 then
    table.insert(lines, '')
    table.insert(lines, '▸ Model 类型不匹配 (' .. #diff.type_mismatch_in_model .. '):')
    for _, entry in ipairs(diff.type_mismatch_in_model) do
      table.insert(lines, '    ' .. entry.name .. ': 期望 ' .. entry.expected .. ', 实际 ' .. entry.actual .. '  (⚠ 不自动修复)')
    end
  end

  -- 创建浮窗
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buftype = 'nofile'

  local width = 80
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line) + 4)
  end
  width = math.min(width, vim.o.columns - 4)
  local height = math.min(#lines, vim.o.lines - 6)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' Datasource Sync ',
    title_pos = 'center',
    footer = ' q: 关闭  y: 确认应用 ',
    footer_pos = 'center',
  })
  vim.wo[win].wrap = false

  local closed = false
  local function close_win()
    if closed then
      return
    end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set('n', 'q', close_win, { buffer = buf, silent = true })
  vim.keymap.set('n', '<Esc>', close_win, { buffer = buf, silent = true })
  vim.keymap.set('n', 'y', function()
    close_win()
    on_confirm()
  end, { buffer = buf, silent = true })

  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = buf,
    once = true,
    callback = close_win,
  })
end

-- ╭──────────────────────────────────────────────────────────╮
-- │ 10. apply_fix                                            │
-- ╰──────────────────────────────────────────────────────────╯

--- 将 diff 中的缺失项写入 mapper XML 和 model Java 文件
---@param diff table
---@param mapper_xml_path string
---@param model_java_path string
---@param has_data_annotation boolean 是否有 @Data 注解
function M.apply_fix(diff, mapper_xml_path, model_java_path, has_data_annotation)
  -- ── 补齐 resultMap ──
  if #diff.missing_in_resultmap > 0 and is_file(mapper_xml_path) then
    local xml_lines = read_file(mapper_xml_path)
    -- 找到最后一个 </resultMap> 之前插入
    -- 从后往前找第一个 </resultMap>
    local insert_indices = {}
    for i = #xml_lines, 1, -1 do
      if xml_lines[i]:match('</resultMap>') then
        table.insert(insert_indices, 1, i)
      end
    end

    if #insert_indices > 0 then
      -- 在最后一个 </resultMap> 前插入
      local insert_at = insert_indices[#insert_indices]
      -- 检测缩进：取 </resultMap> 行的缩进再加两个空格
      local indent = xml_lines[insert_at]:match('^(%s*)') or ''
      indent = indent .. '    '

      local new_lines = {}
      for _, entry in ipairs(diff.missing_in_resultmap) do
        local tag = indent .. '<result column="' .. entry.column
          .. '" property="' .. entry.property
          .. '" jdbcType="' .. entry.jdbc_type .. '"/>'
        table.insert(new_lines, tag)
      end

      -- 逆序插入以保持正确顺序
      for i = #new_lines, 1, -1 do
        table.insert(xml_lines, insert_at, new_lines[i])
      end

      write_file(mapper_xml_path, table.concat(xml_lines, '\n'))
      vim.notify('[datasource] resultMap 已补齐 ' .. #diff.missing_in_resultmap .. ' 个字段', vim.log.levels.INFO)
    end
  end

  -- ── 补齐 Model 字段 ──
  if #diff.missing_in_model > 0 and is_file(model_java_path) then
    local model_lines = read_file(model_java_path)
    local model_text = table.concat(model_lines, '\n')

    -- 先确认字段不存在（再次检查）
    local fields_to_add = {}
    for _, entry in ipairs(diff.missing_in_model) do
      -- 用简单模式检测字段是否已存在
      local field_pattern = '%s' .. vim.pesc(entry.name) .. '%s*[=;]'
      if not model_text:match(field_pattern) then
        table.insert(fields_to_add, entry)
      end
    end

    if #fields_to_add > 0 then
      -- 查找类体中最后一个字段声明或者类声明后插入
      -- 策略：找到最后一个 private/protected/public 字段声明的位置，在其后插入
      local last_field_line = nil
      for i, line in ipairs(model_lines) do
        if line:match('^%s*private%s+') or line:match('^%s*protected%s+') or line:match('^%s*public%s+[%w_<>%[%]]+%s+[%w_]+%s*[=;]') then
          last_field_line = i
        end
      end

      -- 如果没有找到字段，找类声明行
      if not last_field_line then
        for i, line in ipairs(model_lines) do
          if line:match('class%s+%w+') then
            last_field_line = i + 1
            break
          end
        end
      end

      if last_field_line then
        -- 需要添加的 import
        local needs_date = false
        local needs_big_decimal = false
        for _, entry in ipairs(fields_to_add) do
          if entry.java_type == 'Date' then
            needs_date = true
          elseif entry.java_type == 'BigDecimal' then
            needs_big_decimal = true
          end
        end

        -- 检查并添加 import
        local imports_to_add = {}
        if needs_date and not model_text:match('import%s+java%.util%.Date') then
          table.insert(imports_to_add, 'import java.util.Date;')
        end
        if needs_big_decimal and not model_text:match('import%s+java%.math%.BigDecimal') then
          table.insert(imports_to_add, 'import java.math.BigDecimal;')
        end

        if #imports_to_add > 0 then
          -- 找到 import 区的末尾
          local last_import_line = 0
          for i, line in ipairs(model_lines) do
            if line:match('^%s*import%s+') then
              last_import_line = i
            end
          end
          if last_import_line > 0 then
            for idx, imp in ipairs(imports_to_add) do
              table.insert(model_lines, last_import_line + idx, imp)
              -- 调整后续行号
              last_field_line = last_field_line + 1
            end
          end
        end

        -- 生成字段声明和可选的 getter/setter
        local new_lines = {}
        for _, entry in ipairs(fields_to_add) do
          table.insert(new_lines, '')
          table.insert(new_lines, '    private ' .. entry.java_type .. ' ' .. entry.name .. ';')

          if not has_data_annotation then
            -- getter
            local capitalized = entry.name:sub(1, 1):upper() .. entry.name:sub(2)
            local getter_prefix = entry.java_type == 'Boolean' and 'is' or 'get'
            table.insert(new_lines, '')
            table.insert(new_lines, '    public ' .. entry.java_type .. ' ' .. getter_prefix .. capitalized .. '() {')
            table.insert(new_lines, '        return ' .. entry.name .. ';')
            table.insert(new_lines, '    }')

            -- setter
            table.insert(new_lines, '')
            table.insert(new_lines, '    public void set' .. capitalized .. '(' .. entry.java_type .. ' ' .. entry.name .. ') {')
            table.insert(new_lines, '        this.' .. entry.name .. ' = ' .. entry.name .. ';')
            table.insert(new_lines, '    }')
          end
        end

        for i = #new_lines, 1, -1 do
          table.insert(model_lines, last_field_line + 1, new_lines[i])
        end

        write_file(model_java_path, table.concat(model_lines, '\n'))
        vim.notify('[datasource] Model 已补齐 ' .. #fields_to_add .. ' 个字段', vim.log.levels.INFO)
      end
    end
  end

  -- ── 类型不匹配仅警告 ──
  if #diff.type_mismatch_in_model > 0 then
    for _, entry in ipairs(diff.type_mismatch_in_model) do
      vim.notify(
        string.format('[datasource] 类型不匹配: %s 期望 %s, 实际 %s', entry.name, entry.expected, entry.actual),
        vim.log.levels.WARN
      )
    end
  end
end

-- ╭──────────────────────────────────────────────────────────╮
-- │ 11. sync_project — 主流程编排                             │
-- ╰──────────────────────────────────────────────────────────╯

--- 主流程：扫描所有 mapper.xml，逐一比对并提供修复
function M.sync_project()
  local config = M.load_config()
  if not config then
    return
  end

  local annotation_config = config.table_annotation
  if not annotation_config or not annotation_config.class then
    vim.notify('[datasource] 配置缺少 table_annotation', vim.log.levels.WARN)
    return
  end

  local root = project.root()

  -- 查找所有 mapper.xml
  local xml_files = vim.fs.find(function(name)
    return name:match('Mapper%.xml$') ~= nil or name:match('mapper%.xml$') ~= nil
  end, {
    path = root,
    type = 'file',
    limit = 200,
  })

  if #xml_files == 0 then
    vim.notify('[datasource] 项目中未找到 mapper.xml', vim.log.levels.INFO)
    return
  end

  -- 收集所有待处理项
  local tasks = {}

  for _, xml_path in ipairs(xml_files) do
    local entries, metas = M.parse_resultmap(xml_path)

    for _, meta in ipairs(metas) do
      if meta.type then
        -- resultMap 的 type 属性即 model 类全限定名
        local model_fqn = meta.type

        -- 从 FQN 推导 model Java 文件路径
        local model_simple_name = model_fqn:match('([^%.]+)$')
        local model_file, _ = project.find_exact_file(model_simple_name .. '.java', { root = root })

        -- 获取 mapper Java 文件路径 (通过 namespace)
        local xml_content = read_file_text(xml_path)
        local namespace = xml_content:match('<mapper.-namespace%s*=%s*"([^"]+)"')
        local mapper_java_path
        if namespace then
          local mapper_simple_name = namespace:match('([^%.]+)$')
          if mapper_simple_name then
            mapper_java_path = project.find_exact_file(mapper_simple_name .. '.java', { root = root })
          end
        end

        -- 查找表名：先从 model 找，再从 mapper 找
        local table_name
        if model_file then
          table_name = M.find_table_name(model_file, annotation_config)
        end
        if not table_name and mapper_java_path then
          table_name = M.find_table_name(mapper_java_path, annotation_config)
        end

        if table_name and model_file then
          table.insert(tasks, {
            xml_path = xml_path,
            model_path = model_file,
            mapper_java_path = mapper_java_path,
            table_name = table_name,
            resultmap_entries = entries,
          })
        end
      end
    end
  end

  if #tasks == 0 then
    vim.notify('[datasource] 未找到可同步的 mapper (需要有 resultMap 且能定位到表名)', vim.log.levels.INFO)
    return
  end

  -- 逐个处理 task（串行异步）
  local function process_task(index)
    if index > #tasks then
      vim.notify('[datasource] 同步完成', vim.log.levels.INFO)
      return
    end

    local task = tasks[index]

    M.fetch_table_columns(config, task.table_name, function(columns, err)
      if err then
        vim.notify('[datasource] 获取表 ' .. task.table_name .. ' 失败: ' .. err, vim.log.levels.ERROR)
        process_task(index + 1)
        return
      end

      if not columns or #columns == 0 then
        vim.notify('[datasource] 表 ' .. task.table_name .. ' 没有列信息', vim.log.levels.WARN)
        process_task(index + 1)
        return
      end

      local model_fields, has_data = M.parse_model_fields(task.model_path)
      local diff = M.compute_diff(columns, task.resultmap_entries, model_fields)

      if is_diff_empty(diff) then
        -- 没有差异，跳过
        process_task(index + 1)
        return
      end

      -- 用浮窗展示差异让用户确认
      show_diff_window(diff, {
        table_name = task.table_name,
        mapper_xml = project.relative(task.xml_path),
        model_java = project.relative(task.model_path),
      }, function()
        M.apply_fix(diff, task.xml_path, task.model_path, has_data)

        -- 如果修改的文件已在 buffer 中打开，重新加载
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(bufnr) then
            local buf_name = vim.api.nvim_buf_get_name(bufnr)
            if buf_name == task.xml_path or buf_name == task.model_path then
              vim.api.nvim_buf_call(bufnr, function()
                vim.cmd('silent! checktime')
                vim.cmd('silent! edit')
              end)
            end
          end
        end

        -- 处理下一个
        vim.defer_fn(function()
          process_task(index + 1)
        end, 300)
      end)
    end)
  end

  -- 让用户选择处理哪些表，或者全部处理
  if #tasks == 1 then
    process_task(1)
  else
    local items = { '全部同步 (' .. #tasks .. ' 个表)' }
    for _, task in ipairs(tasks) do
      table.insert(items, task.table_name .. ' ← ' .. vim.fn.fnamemodify(task.xml_path, ':t'))
    end

    vim.ui.select(items, { prompt = 'Datasource Sync' }, function(_, idx)
      if not idx then
        return
      end
      if idx == 1 then
        -- 全部处理
        process_task(1)
      else
        -- 只处理选中的那个
        process_task(idx - 1)
      end
    end)
  end
end

-- ╭──────────────────────────────────────────────────────────╮
-- │ Commands & Autocmds                                      │
-- ╰──────────────────────────────────────────────────────────╯

local CONFIG_TEMPLATE = vim.json.encode({
  host = 'localhost',
  port = 3306,
  user = 'root',
  password = '',
  database = 'mydb',
  skip_ssl = true,
  table_annotation = {
    class = 'Table',
    field = 'table',
  },
})

--- 注册命令和自动命令
function M.setup()
  -- :DatasourceSync — 手动触发同步
  vim.api.nvim_create_user_command('DatasourceSync', function()
    M.sync_project()
  end, {
    desc = '同步数据库表结构到 MyBatis resultMap 和 Java Model',
  })

  -- :DatasourceConfig — 打开（或创建）配置文件
  vim.api.nvim_create_user_command('DatasourceConfig', function()
    local config_path = project.config_path(CONFIG_FILENAME)
    if not is_file(config_path) then
      -- 创建模板
      local formatted = vim.fn.system({ 'python3', '-m', 'json.tool' }, CONFIG_TEMPLATE)
      if vim.v.shell_error ~= 0 then
        formatted = CONFIG_TEMPLATE
      end
      vim.fn.writefile(vim.split(formatted, '\n', { plain = true }), config_path)
      vim.notify('[datasource] 已创建配置文件模板: ' .. config_path, vim.log.levels.INFO)
    end
    vim.cmd('edit ' .. vim.fn.fnameescape(config_path))
  end, {
    desc = '打开数据源配置文件',
  })

  -- LspAttach 自动触发：jdtls 附加后延迟 5 秒自动同步
  local group = vim.api.nvim_create_augroup('UserDatasourceSync', { clear = true })
  vim.api.nvim_create_autocmd('LspAttach', {
    group = group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if not client or client.name ~= 'jdtls' then
        return
      end

      -- 延迟 5 秒后异步执行同步
      vim.defer_fn(function()
        -- 只在配置文件存在时才自动同步，避免无用报错
        local config_path = project.config_path(CONFIG_FILENAME)
        if is_file(config_path) then
          M.sync_project()
        end
      end, 5000)
    end,
  })
end

return M
