local M = {}

local sessions = {}
local ns = vim.api.nvim_create_namespace('user_json_meta')

local function deepcopy(value)
  return vim.deepcopy(value)
end

local function is_list(value)
  return vim.islist(value)
end

local function path_key(path)
  local parts = {}
  for _, segment in ipairs(path or {}) do
    table.insert(parts, tostring(segment))
  end
  return table.concat(parts, '\31')
end

local function decode_json_file(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end

  local lines = vim.fn.readfile(path)
  if #lines == 0 then
    return nil
  end

  return vim.json.decode(table.concat(lines, '\n'))
end

local function required_set(schema)
  local result = {}
  for _, name in ipairs(schema.required or {}) do
    result[name] = true
  end
  return result
end

local function schema_type(schema)
  if schema.type then
    return schema.type
  end
  if schema.properties then
    return 'object'
  end
  if schema.items then
    return 'array'
  end
  return 'string'
end

local function default_value(schema, force_required)
  if schema.default ~= nil then
    return deepcopy(schema.default)
  end

  local value_type = schema_type(schema)
  if value_type == 'object' then
    local value = {}
    local required = required_set(schema)
    for key, child in pairs(schema.properties or {}) do
      if required[key] or child.default ~= nil or force_required then
        value[key] = default_value(child, required[key] or force_required)
      end
    end
    return value
  end

  if value_type == 'array' then
    return {}
  end

  if value_type == 'boolean' then
    return false
  end

  if value_type == 'number' or value_type == 'integer' then
    return 0
  end

  if value_type == 'json' then
    return {}
  end

  return ''
end

local function normalize_value(value, schema, force_required)
  local value_type = schema_type(schema)
  if value == nil then
    if force_required then
      return default_value(schema, true)
    end
    if value_type == 'array' then
      return {}
    end
    if value_type == 'object' then
      return {}
    end
    return nil
  end

  if value_type == 'object' then
    local result = type(value) == 'table' and not is_list(value) and deepcopy(value) or {}
    local required = required_set(schema)
    for key, child in pairs(schema.properties or {}) do
      result[key] = normalize_value(result[key], child, required[key])
    end
    return result
  end

  if value_type == 'array' then
    local list = type(value) == 'table' and is_list(value) and deepcopy(value) or {}
    for index, item in ipairs(list) do
      list[index] = normalize_value(item, schema.items or { type = 'string' }, true)
    end
    return list
  end

  return deepcopy(value)
end

local function pretty_json(value, indent)
  indent = indent or 0
  local prefix = string.rep('  ', indent)
  local child_prefix = string.rep('  ', indent + 1)

  if value == nil then
    return 'null'
  end

  if type(value) == 'string' then
    return vim.json.encode(value)
  end

  if type(value) == 'number' or type(value) == 'boolean' then
    return tostring(value)
  end

  if is_list(value) then
    if #value == 0 then
      return '[]'
    end

    local parts = { '[' }
    for index, item in ipairs(value) do
      local suffix = index < #value and ',' or ''
      table.insert(parts, child_prefix .. pretty_json(item, indent + 1) .. suffix)
    end
    table.insert(parts, prefix .. ']')
    return table.concat(parts, '\n')
  end

  local keys = vim.tbl_keys(value)
  table.sort(keys)
  if #keys == 0 then
    return '{}'
  end

  local parts = { '{' }
  for index, key in ipairs(keys) do
    local suffix = index < #keys and ',' or ''
    table.insert(parts, child_prefix .. vim.json.encode(key) .. ': ' .. pretty_json(value[key], indent + 1) .. suffix)
  end
  table.insert(parts, prefix .. '}')
  return table.concat(parts, '\n')
end

local function save_json_file(path, value)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  vim.fn.writefile(vim.split(pretty_json(value), '\n', { plain = true }), path)
end

local function get_at_path(root, path)
  local current = root
  for _, segment in ipairs(path) do
    if type(current) ~= 'table' then
      return nil
    end
    current = current[segment]
  end
  return current
end

local function set_at_path(root, path, value)
  if #path == 0 then
    return value
  end

  local current = root
  for index = 1, #path - 1 do
    local segment = path[index]
    local next_segment = path[index + 1]
    if current[segment] == nil then
      current[segment] = type(next_segment) == 'number' and {} or {}
    end
    current = current[segment]
  end

  local last = path[#path]
  current[last] = value
  return root
end

local function remove_at_path(root, path)
  if #path == 0 then
    return root
  end

  local current = root
  for index = 1, #path - 1 do
    current = current[path[index]]
    if type(current) ~= 'table' then
      return root
    end
  end

  current[path[#path]] = nil
  return root
end

local function scalar_display(value, schema)
  local value_type = schema_type(schema)
  if value == nil then
    return ''
  end

  if value_type == 'json' then
    return vim.json.encode(value)
  end

  if value_type == 'boolean' then
    return value and 'true' or 'false'
  end

  return tostring(value)
end

local function parse_scalar(text, schema, required)
  local value_type = schema_type(schema)
  if text == '' then
    if required then
      return default_value(schema, true)
    end
    return nil
  end

  if value_type == 'string' then
    return text
  end

  if value_type == 'boolean' then
    if text == 'true' then
      return true
    end
    if text == 'false' then
      return false
    end
    error('Boolean value must be true or false.')
  end

  if value_type == 'integer' then
    local number = tonumber(text)
    if not number or math.floor(number) ~= number then
      error('Integer value is required.')
    end
    return math.floor(number)
  end

  if value_type == 'number' then
    local number = tonumber(text)
    if not number then
      error('Number value is required.')
    end
    return number
  end

  if value_type == 'json' then
    return vim.json.decode(text)
  end

  return text
end

local function add_line(state, text, meta)
  table.insert(state.lines, text)
  local lnum = #state.lines
  state.line_meta[lnum] = meta
  if meta and meta.array_path then
    state.array_meta[path_key(meta.array_path) .. '\31' .. tostring(meta.array_index or 0)] = {
      path = deepcopy(meta.array_path),
      index = meta.array_index,
      schema = meta.array_schema,
    }
  end
  return lnum
end

local function add_description(state, indent, description, meta)
  if not description or description == '' then
    return
  end
  add_line(state, indent .. '# ' .. description, meta)
end

local function render_scalar_field(state, path, name, value, schema, indent, required, array_path, array_index, array_schema)
  local key_label = name
  if required then
    key_label = key_label .. ' *'
  end

  local prefix = indent .. key_label .. ': '
  local line = prefix .. scalar_display(value, schema)
  local lnum = add_line(state, line, {
    kind = 'field',
    path = deepcopy(path),
    prefix = prefix,
    schema = schema,
    required = required,
    array_path = array_path and deepcopy(array_path) or nil,
    array_index = array_index,
    array_schema = array_schema,
  })

  local field = {
    key = path_key(path),
    path = deepcopy(path),
    line = lnum,
    prefix = prefix,
    schema = schema,
    required = required,
    array_path = array_path and deepcopy(array_path) or nil,
    array_index = array_index,
  }
  state.fields[#state.fields + 1] = field
  state.field_by_line[lnum] = #state.fields
  add_description(state, indent .. '  ', schema.description, state.line_meta[lnum])
end

local render_node

local function render_object(state, path, value, schema, indent, array_path, array_index, array_schema)
  local required = required_set(schema)
  local keys = vim.tbl_keys(schema.properties or {})
  table.sort(keys)
  for _, key in ipairs(keys) do
    local child_schema = schema.properties[key]
    local child_path = deepcopy(path)
    child_path[#child_path + 1] = key
    local child_value = value[key]
    local child_type = schema_type(child_schema)

    if child_type == 'object' or child_type == 'array' then
      local label = key
      if required[key] then
        label = label .. ' *'
      end
      local line_meta = {
        kind = child_type,
        path = deepcopy(child_path),
        array_path = array_path and deepcopy(array_path) or nil,
        array_index = array_index,
      }
      add_line(state, indent .. label .. ':', line_meta)
      add_description(state, indent .. '  ', child_schema.description, line_meta)
      render_node(state, child_path, child_value, child_schema, indent .. '  ', array_path, array_index)
    else
      render_scalar_field(state, child_path, key, child_value, child_schema, indent, required[key], array_path, array_index, array_schema)
    end
  end
end

local function render_array(state, path, value, schema, indent)
  local items = value or {}
  local item_schema = schema.items or { type = 'string' }

  if #items == 0 then
    local meta = {
      kind = 'array-empty',
      path = deepcopy(path),
      array_path = deepcopy(path),
      array_index = 0,
      array_schema = schema,
    }
    add_line(state, indent .. '<empty array>  (+/= insert item)', meta)
    return
  end

  for index, item in ipairs(items) do
    local item_path = deepcopy(path)
    item_path[#item_path + 1] = index
    local header_meta = {
      kind = 'array-item',
      path = deepcopy(item_path),
      array_path = deepcopy(path),
      array_index = index,
      array_schema = schema,
    }
    add_line(state, indent .. string.format('- item %d', index), header_meta)

    local item_type = schema_type(item_schema)
    if item_type == 'object' then
      render_object(state, item_path, item, item_schema, indent .. '  ', path, index, schema)
    elseif item_type == 'array' then
      render_array(state, item_path, item, item_schema, indent .. '  ')
    else
      local prefix = indent .. '  - '
      local lnum = add_line(state, prefix .. scalar_display(item, item_schema), {
        kind = 'field',
        path = deepcopy(item_path),
        prefix = prefix,
        schema = item_schema,
        required = true,
        array_path = deepcopy(path),
        array_index = index,
        array_schema = schema,
      })
      state.fields[#state.fields + 1] = {
        key = path_key(item_path),
        path = deepcopy(item_path),
        line = lnum,
        prefix = prefix,
        schema = item_schema,
        required = true,
        array_path = deepcopy(path),
        array_index = index,
      }
      state.field_by_line[lnum] = #state.fields
      add_description(state, indent .. '    ', item_schema.description, state.line_meta[lnum])
    end
  end
end

render_node = function(state, path, value, schema, indent, array_path, array_index)
  local value_type = schema_type(schema)
  if value_type == 'object' then
    render_object(state, path, value or {}, schema, indent, array_path, array_index, nil)
    return
  end

  if value_type == 'array' then
    render_array(state, path, value or {}, schema, indent)
    return
  end
end

local function find_field_index(state, key)
  if not key then
    return nil
  end
  for index, field in ipairs(state.fields) do
    if field.key == key then
      return index
    end
  end
end

local function current_field(state)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local index = state.field_by_line[line]
  return index and state.fields[index], index
end

local function value_col(field)
  return #field.prefix
end

local function highlight(state)
  vim.api.nvim_buf_clear_namespace(state.bufnr, ns, 0, -1)

  for lnum, meta in pairs(state.line_meta) do
    if meta.kind == 'field' then
      vim.api.nvim_buf_add_highlight(state.bufnr, ns, 'Identifier', lnum - 1, 0, #meta.prefix)
      local line = state.lines[lnum] or ''
      if line == meta.prefix and meta.required then
        vim.api.nvim_buf_add_highlight(state.bufnr, ns, 'DiagnosticWarn', lnum - 1, #meta.prefix, -1)
      end
    elseif meta.kind == 'array-item' then
      vim.api.nvim_buf_add_highlight(state.bufnr, ns, 'Title', lnum - 1, 0, -1)
    elseif meta.kind == 'array-empty' then
      vim.api.nvim_buf_add_highlight(state.bufnr, ns, 'Comment', lnum - 1, 0, -1)
    else
      local line = state.lines[lnum] or ''
      if vim.startswith(vim.trim(line), '#') then
        vim.api.nvim_buf_add_highlight(state.bufnr, ns, 'Comment', lnum - 1, 0, -1)
      end
    end
  end
end

local function render(state, restore_key)
  state.lines = {}
  state.fields = {}
  state.field_by_line = {}
  state.line_meta = {}
  state.array_meta = {}

  if state.title and state.title ~= '' then
    add_line(state, '# ' .. state.title, { kind = 'title' })
    if state.description and state.description ~= '' then
      add_line(state, '# ' .. state.description, { kind = 'description' })
    end
    add_line(state, '', { kind = 'spacer' })
  end

  render_node(state, {}, state.data, state.schema, '', nil, nil)

  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, state.lines)
  highlight(state)

  local field_index = find_field_index(state, restore_key)
  if not field_index and #state.fields > 0 then
    field_index = 1
  end

  if field_index then
    local field = state.fields[field_index]
    vim.api.nvim_win_set_cursor(state.winid, { field.line, value_col(field) })
  end
end

local function parse_field_line(state, field)
  local line = vim.api.nvim_buf_get_lines(state.bufnr, field.line - 1, field.line, false)[1] or ''
  local value_text = ''

  if vim.startswith(line, field.prefix) then
    value_text = line:sub(#field.prefix + 1)
  else
    local colon_index = line:find(':', 1, true)
    if colon_index then
      value_text = vim.trim(line:sub(colon_index + 1))
    elseif vim.startswith(vim.trim(line), '- ') then
      value_text = vim.trim(line):sub(3)
    end
  end

  local ok, parsed = pcall(parse_scalar, value_text, field.schema, field.required)
  if not ok then
    vim.notify(parsed, vim.log.levels.ERROR)
    return false
  end

  if parsed == nil then
    remove_at_path(state.data, field.path)
  else
    set_at_path(state.data, field.path, parsed)
  end
  return true
end

local function parse_current_field(state)
  local field = current_field(state)
  if not field then
    return true
  end
  return parse_field_line(state, field)
end

local function parse_all_fields(state)
  for _, field in ipairs(state.fields) do
    if not parse_field_line(state, field) then
      return false
    end
  end
  return true
end

local function move_to_field(state, index, insert_mode)
  if #state.fields == 0 then
    return
  end

  if index < 1 then
    index = #state.fields
  elseif index > #state.fields then
    index = 1
  end

  local field = state.fields[index]
  vim.api.nvim_win_set_cursor(state.winid, { field.line, value_col(field) })
  if insert_mode then
    vim.cmd('startinsert')
  end
end

local function advance_field(state, delta, insert_mode)
  if not parse_current_field(state) then
    return
  end

  local _, index = current_field(state)
  if not index then
    index = 0
  end

  render(state, current_field(state) and current_field(state).key or nil)
  move_to_field(state, index + delta, insert_mode)
end

local function current_array_context(state)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local meta = state.line_meta[line]
  if not meta or not meta.array_path then
    return nil
  end

  return {
    path = deepcopy(meta.array_path),
    index = meta.array_index or 0,
    schema = meta.array_schema or get_at_path(state.schema, meta.array_path),
  }
end

local function insert_array_item(state, below)
  local ctx = current_array_context(state)
  if not ctx or not ctx.schema or schema_type(ctx.schema) ~= 'array' then
    vim.notify('Current line is not inside an editable array item.', vim.log.levels.WARN)
    return
  end

  if not parse_all_fields(state) then
    return
  end

  local array = get_at_path(state.data, ctx.path)
  if type(array) ~= 'table' or not is_list(array) then
    array = {}
    set_at_path(state.data, ctx.path, array)
  end

  local index = ctx.index
  if index == 0 then
    index = 1
  elseif below then
    index = index + 1
  end

  table.insert(array, index, default_value(ctx.schema.items or { type = 'string' }, true))
  render(state, path_key(vim.list_extend(deepcopy(ctx.path), { index })))
end

local function delete_array_item(state)
  local ctx = current_array_context(state)
  if not ctx or ctx.index == 0 or not ctx.schema or schema_type(ctx.schema) ~= 'array' then
    vim.notify('Current line is not inside an array item.', vim.log.levels.WARN)
    return
  end

  if not parse_all_fields(state) then
    return
  end

  local array = get_at_path(state.data, ctx.path)
  if type(array) ~= 'table' or not is_list(array) then
    return
  end

  table.remove(array, ctx.index)
  render(state, nil)
end

local function move_array_item(state, delta)
  local ctx = current_array_context(state)
  if not ctx or ctx.index == 0 or not ctx.schema or schema_type(ctx.schema) ~= 'array' then
    return false
  end

  if not parse_all_fields(state) then
    return true
  end

  local array = get_at_path(state.data, ctx.path)
  if type(array) ~= 'table' or not is_list(array) then
    return true
  end

  local new_index = ctx.index + delta
  if new_index < 1 or new_index > #array then
    return true
  end

  local item = table.remove(array, ctx.index)
  table.insert(array, new_index, item)
  render(state, path_key(vim.list_extend(deepcopy(ctx.path), { new_index })))
  return true
end

local function clear_current_value(state)
  local field = current_field(state)
  if not field then
    return
  end

  if not parse_all_fields(state) then
    return
  end

  local replacement = field.required and default_value(field.schema, true) or nil
  if replacement == nil then
    remove_at_path(state.data, field.path)
  else
    set_at_path(state.data, field.path, replacement)
  end
  render(state, field.key)
end

local function collect_errors(value, schema, path, errors)
  errors = errors or {}
  path = path or {}
  local value_type = schema_type(schema)

  if value_type == 'object' then
    local required = required_set(schema)
    for key, child in pairs(schema.properties or {}) do
      local child_path = deepcopy(path)
      child_path[#child_path + 1] = key
      local child_value = value and value[key] or nil
      if required[key] and (child_value == nil or child_value == '') then
        errors[#errors + 1] = table.concat(child_path, '.')
      end
      collect_errors(child_value, child, child_path, errors)
    end
    return errors
  end

  if value_type == 'array' then
    for index, item in ipairs(value or {}) do
      local child_path = deepcopy(path)
      child_path[#child_path + 1] = index
      collect_errors(item, schema.items or { type = 'string' }, child_path, errors)
    end
    return errors
  end

  return errors
end

local function save_state(state)
  if not parse_all_fields(state) then
    return false
  end

  local errors = collect_errors(state.data, state.schema, {}, {})
  if #errors > 0 then
    vim.notify('Required fields are still empty: ' .. table.concat(errors, ', '), vim.log.levels.ERROR)
    return false
  end

  save_json_file(state.target_path, state.data)
  vim.notify('Saved ' .. state.target_path, vim.log.levels.INFO)
  render(state, current_field(state) and current_field(state).key or nil)
  return true
end

local function state_for_buf(bufnr)
  return sessions[bufnr]
end

local function setup_buffer(state)
  vim.bo[state.bufnr].buftype = 'acwrite'
  vim.bo[state.bufnr].bufhidden = 'wipe'
  vim.bo[state.bufnr].swapfile = false
  vim.bo[state.bufnr].filetype = 'jsonmeta'
  vim.bo[state.bufnr].modifiable = true

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = state.bufnr,
    callback = function()
      save_state(state)
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = state.bufnr,
    callback = function()
      sessions[state.bufnr] = nil
    end,
  })

  vim.keymap.set({ 'n', 'i' }, '<Tab>', function()
    advance_field(state, 1, vim.api.nvim_get_mode().mode:sub(1, 1) == 'i')
  end, { buffer = state.bufnr, silent = true, desc = 'Next editable value' })

  vim.keymap.set({ 'n', 'i' }, '<S-Tab>', function()
    advance_field(state, -1, vim.api.nvim_get_mode().mode:sub(1, 1) == 'i')
  end, { buffer = state.bufnr, silent = true, desc = 'Previous editable value' })

  vim.keymap.set('n', '+', function()
    insert_array_item(state, false)
  end, { buffer = state.bufnr, silent = true, desc = 'Insert array item above' })

  vim.keymap.set('n', '=', function()
    insert_array_item(state, true)
  end, { buffer = state.bufnr, silent = true, desc = 'Insert array item below' })

  vim.keymap.set('n', '-', function()
    delete_array_item(state)
  end, { buffer = state.bufnr, silent = true, desc = 'Delete current array item' })

  vim.keymap.set('n', 'dd', function()
    clear_current_value(state)
  end, { buffer = state.bufnr, silent = true, desc = 'Clear current value' })

  local function move_item(delta)
    if move_array_item(state, delta) then
      return
    end
    if delta > 0 then
      require('user.text_move').move_line_down()
    else
      require('user.text_move').move_line_up()
    end
  end

  vim.keymap.set('n', '<M-J>', function() move_item(1) end, { buffer = state.bufnr, silent = true, desc = 'Move item down' })
  vim.keymap.set('n', '<M-K>', function() move_item(-1) end, { buffer = state.bufnr, silent = true, desc = 'Move item up' })
  vim.keymap.set('n', '<M-S-Down>', function() move_item(1) end, { buffer = state.bufnr, silent = true, desc = 'Move item down' })
  vim.keymap.set('n', '<M-S-Up>', function() move_item(-1) end, { buffer = state.bufnr, silent = true, desc = 'Move item up' })

  vim.keymap.set({ 'n', 'i' }, '<C-s>', function()
    save_state(state)
  end, { buffer = state.bufnr, silent = true, desc = 'Save JSON meta buffer' })
end

local function load_schema(schema_or_path)
  if type(schema_or_path) == 'table' then
    return deepcopy(schema_or_path)
  end

  local value = decode_json_file(schema_or_path)
  if not value then
    error('Could not read meta schema: ' .. tostring(schema_or_path))
  end
  return value
end

function M.open(target_path, schema_or_path, opts)
  opts = opts or {}
  local schema = load_schema(schema_or_path)
  local initial = decode_json_file(target_path)
  local data = normalize_value(initial, schema, true)
  if data == nil then
    data = default_value(schema, true)
  end

  vim.cmd(opts.split_cmd or 'botright 18split')
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(winid, bufnr)
  vim.api.nvim_buf_set_name(bufnr, string.format('json-meta://%s', target_path))

  local state = {
    bufnr = bufnr,
    winid = winid,
    target_path = target_path,
    schema = schema,
    data = data,
    title = opts.title or schema.title or vim.fn.fnamemodify(target_path, ':t'),
    description = opts.description or schema.description or '',
  }
  sessions[bufnr] = state

  setup_buffer(state)
  render(state, nil)
  return bufnr
end

function M.setup()
  vim.api.nvim_create_user_command('JsonMetaEdit', function(opts)
    if #opts.fargs < 2 then
      vim.notify('Usage: JsonMetaEdit <target.json> <meta.json>', vim.log.levels.ERROR)
      return
    end

    M.open(vim.fn.expand(opts.fargs[1]), vim.fn.expand(opts.fargs[2]))
  end, {
    nargs = '+',
    complete = 'file',
    desc = 'Open a schema-driven JSON editor',
  })
end

return M
