local project = require('user.project')

local M = {}

local function normalize(path)
  if not path or path == '' then
    return nil
  end

  return vim.fs.normalize(path)
end

local function open_at(path, line_nr, col_nr, cmd)
  local normalized = normalize(path)
  if not normalized or not vim.uv.fs_stat(normalized) then
    return false, 'Target file does not exist: ' .. tostring(path)
  end

  vim.cmd((cmd or 'edit') .. ' ' .. vim.fn.fnameescape(normalized))
  vim.api.nvim_win_set_cursor(0, {
    math.max(line_nr or 1, 1),
    math.max((col_nr or 1) - 1, 0),
  })
  vim.cmd('normal! zz')
  return true
end

local function package_name_for_file(path)
  local lines = vim.fn.readfile(path, '', 120)
  for _, line in ipairs(lines) do
    local package_name = line:match('^%s*package%s+([%w_%.]+)%s*;')
    if package_name then
      return package_name
    end
  end
end

local function parse_path_ref(text)
  local quoted_path, quoted_line = text:match('File "([^"]+)", line (%d+)')
  if quoted_path and quoted_line then
    return {
      kind = 'path',
      path = quoted_path,
      line = tonumber(quoted_line),
      col = 1,
    }
  end

  local path_part, line_part, col_part = text:match('([%a]:[%w%._%-%/%\\]+%.[%w]+):(%d+):(%d+)')
  if not path_part then
    path_part, line_part = text:match('([%a]:[%w%._%-%/%\\]+%.[%w]+):(%d+)')
  end

  if not path_part then
    path_part, line_part, col_part = text:match('([%w%._%-%/%\\]+%.[%w]+):(%d+):(%d+)')
  end

  if not path_part then
    path_part, line_part = text:match('([%w%._%-%/%\\]+%.[%w]+):(%d+)')
  end

  if not path_part or not line_part then
    return nil
  end

  return {
    kind = 'path',
    path = path_part,
    line = tonumber(line_part),
    col = tonumber(col_part) or 1,
  }
end

local function parse_plain_file_ref(text)
  local path = text:match('([%w%._%-]+%.[%w]+)')
  if not path then
    return nil
  end

  return {
    kind = 'file',
    path = path,
  }
end

local function parse_java_stack_ref(text)
  local fqn, file_name, line_nr = text:match('at%s+([%w_$.]+)%.[%w_$<>]+%(([%w_]+%.java):(%d+)%)')
  if not fqn then
    fqn, file_name, line_nr = text:match('([%w_$.]+)%.[%w_$<>]+%(([%w_]+%.java):(%d+)%)')
  end

  if not fqn or not file_name or not line_nr then
    return nil
  end

  local class_name = fqn:gsub('%$.*$', '')
  local relative_path = class_name:gsub('%.', '/') .. '.java'

  return {
    kind = 'java-stack',
    file_name = file_name,
    line = tonumber(line_nr),
    class_name = class_name,
    relative_path = relative_path,
  }
end

local function parse_java_reference(text)
  local class_name, member_name = text:match('([%w_%.]+)#([%w_$]+)')
  if class_name then
    return {
      kind = 'java-reference',
      class_name = class_name,
      member_name = member_name,
    }
  end

  class_name = text:match('^%s*([%w_%.]+)%s*$')
  if class_name and class_name:find('%.') then
    return {
      kind = 'java-reference',
      class_name = class_name,
    }
  end
end

local function resolve_path_ref(ref, opts)
  opts = opts or {}
  local root = project.root(opts.path)
  local path = normalize(ref.path)
  if path and vim.uv.fs_stat(path) then
    return path
  end

  local joined = normalize(vim.fs.joinpath(root, ref.path))
  if joined and vim.uv.fs_stat(joined) then
    return joined
  end

  return project.find_exact_file(ref.path, { root = root })
end

local function resolve_java_stack_ref(ref, opts)
  opts = opts or {}
  local root = project.root(opts.path)
  local direct = normalize(vim.fs.joinpath(root, 'src/main/java', ref.relative_path))
  if direct and vim.uv.fs_stat(direct) then
    return direct
  end

  local test_path = normalize(vim.fs.joinpath(root, 'src/test/java', ref.relative_path))
  if test_path and vim.uv.fs_stat(test_path) then
    return test_path
  end

  local fallback, err = project.find_exact_file(ref.file_name, { root = root })
  if not fallback then
    return nil, err
  end

  local package_name = package_name_for_file(fallback)
  if package_name and ref.class_name:match('^' .. vim.pesc(package_name) .. '%.') then
    return fallback
  end

  if not package_name then
    return fallback
  end

  return nil, 'Exact Java stack reference did not match the located file package.'
end

local function resolve_java_reference(ref, opts)
  opts = opts or {}
  local root = project.root(opts.path)
  local relative = ref.class_name:gsub('%.', '/') .. '.java'
  for _, source_root in ipairs({ 'src/main/java', 'src/test/java' }) do
    local path = normalize(vim.fs.joinpath(root, source_root, relative))
    if path and vim.uv.fs_stat(path) then
      return path
    end
  end

  local fallback, err = project.find_exact_file(vim.fs.basename(relative), { root = root })
  if not fallback then
    return nil, err
  end

  local package_name = package_name_for_file(fallback)
  if package_name and ref.class_name == package_name .. '.' .. vim.fn.fnamemodify(fallback, ':t:r') then
    return fallback
  end

  if not package_name then
    return fallback
  end

  return nil, 'Exact Java reference did not match the located file package.'
end

local function find_member_line(path, member_name)
  if not member_name then
    return 1
  end

  local lines = vim.fn.readfile(path, '', 400)
  local method_pattern = '%f[%w_]' .. vim.pesc(member_name) .. '%s*%('
  local field_pattern = '%f[%w_]' .. vim.pesc(member_name) .. '%f[^%w_]'

  for index, line in ipairs(lines) do
    if line:match(method_pattern) then
      return index
    end
  end

  for index, line in ipairs(lines) do
    if line:match(field_pattern) then
      return index
    end
  end

  return 1
end

function M.parse_reference(text)
  if type(text) ~= 'string' or vim.trim(text) == '' then
    return nil
  end

  return parse_java_stack_ref(text)
    or parse_path_ref(text)
    or parse_java_reference(vim.trim(text))
    or parse_plain_file_ref(text)
end

function M.jump_reference(text, opts)
  opts = opts or {}
  local ref = type(text) == 'table' and text or M.parse_reference(text)
  if not ref then
    return false, 'Could not parse an exact reference from: ' .. tostring(text)
  end

  if ref.kind == 'path' or ref.kind == 'file' then
    local path, err = resolve_path_ref(ref, opts)
    if not path then
      return false, err
    end
    return open_at(path, ref.line or 1, ref.col or 1, opts.open_cmd)
  end

  if ref.kind == 'java-stack' then
    local path, err = resolve_java_stack_ref(ref, opts)
    if not path then
      return false, err
    end
    return open_at(path, ref.line or 1, 1, opts.open_cmd)
  end

  if ref.kind == 'java-reference' then
    local path, err = resolve_java_reference(ref, opts)
    if not path then
      return false, err
    end
    return open_at(path, find_member_line(path, ref.member_name), 1, opts.open_cmd)
  end

  return false, 'Unsupported exact reference kind: ' .. tostring(ref.kind)
end

local function current_java_member()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, cursor_line, false)

  for index = #lines, 1, -1 do
    local line = lines[index]
    local method_name = line:match('([%w_]+)%s*%(')
    if method_name and method_name ~= vim.fn.expand('%:t:r') and not line:match('if%s*%(') and not line:match('for%s*%(') then
      return method_name
    end

    local field_name = line:match('[%w_%[%]<>%.]+%s+([%u%l_][%w_]*)%s*[=;]')
    if field_name then
      return field_name
    end
  end
end

function M.copy_reference()
  local path = project.path_from_buf(0)
  if not path then
    vim.notify('Current buffer has no file path.', vim.log.levels.WARN)
    return nil
  end

  local reference
  if vim.bo.filetype == 'java' then
    local class_name = vim.fn.fnamemodify(path, ':t:r')
    local package_name = package_name_for_file(path)
    local fqn = package_name and (package_name .. '.' .. class_name) or class_name
    local member_name = current_java_member()
    reference = member_name and (fqn .. '#' .. member_name) or fqn
  else
    reference = string.format('%s:%d', project.relative(path), vim.api.nvim_win_get_cursor(0)[1])
  end

  vim.fn.setreg('+', reference)
  vim.fn.setreg('"', reference)
  vim.notify('Copied reference: ' .. reference, vim.log.levels.INFO)
  return reference
end

function M.jump_current_line()
  local line = vim.api.nvim_get_current_line()
  local ok, err = M.jump_reference(line, { path = project.path_from_buf(0) })
  if ok then
    return
  end

  local keys = vim.api.nvim_replace_termcodes('gF', true, false, true)
  vim.api.nvim_feedkeys(keys, 'n', false)
  if err and not line:find('%f[%w][%w_%.%-/\\]+:%d+') and not line:find('#', 1, true) then
    return
  end
end

function M.prompt_jump()
  local input = vim.fn.input('Jump reference: ')
  if input == '' then
    return
  end

  local ok, err = M.jump_reference(input, { path = project.path_from_buf(0) })
  if not ok then
    vim.notify(err, vim.log.levels.ERROR)
  end
end

function M.setup()
  vim.api.nvim_create_user_command('CopyReference', function()
    M.copy_reference()
  end, {
    desc = 'Copy an exact file or Java reference',
  })

  vim.api.nvim_create_user_command('JumpReference', function(opts)
    if opts.args == '' then
      M.prompt_jump()
      return
    end

    local ok, err = M.jump_reference(opts.args, { path = project.path_from_buf(0) })
    if not ok then
      vim.notify(err, vim.log.levels.ERROR)
    end
  end, {
    nargs = '?',
    complete = 'file',
    desc = 'Jump to an exact file, stack, or Java reference',
  })
end

return M
