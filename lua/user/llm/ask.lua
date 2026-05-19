local client = require('user.llm.client')
local config = require('user.llm.config')
local context = require('user.llm.context')

local M = {}

local sessions = {}

local function get_state(bufnr)
  local state = sessions[bufnr]
  if not state then
    state = {
      buf = bufnr,
      generated_text = '',
      status_text = '',
      output_start = nil,
      prompt_end = nil,
      job_id = nil,
      cancelled = false,
      error_reported = false,
      request_finished = false,
      request_succeeded = false,
      has_content = false,
      has_activity = false,
      last_submitted_prompt = nil,
    }
    sessions[bufnr] = state
  end

  return state
end

local function render_generated(bufnr)
  local state = sessions[bufnr]
  if not state or not state.output_start or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local lines = context.split_lines(state.generated_text)
  vim.api.nvim_buf_set_lines(bufnr, state.output_start - 1, -1, false, lines)
end

local function stop_generation(bufnr)
  local state = sessions[bufnr]
  if not state or not state.job_id then
    return false
  end

  state.cancelled = true
  client.stop(state.job_id)
  state.job_id = nil
  return true
end

local function delete_generated(bufnr)
  local state = sessions[bufnr]
  if not state then
    return
  end

  stop_generation(bufnr)

  if state.prompt_end and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_set_lines(bufnr, state.prompt_end, -1, false, {})
  end

  state.generated_text = ''
  state.status_text = ''
  state.output_start = nil
  state.prompt_end = nil
  state.cancelled = false
  state.error_reported = false
  state.request_finished = false
  state.request_succeeded = false
  state.has_content = false
  state.has_activity = false
  state.last_submitted_prompt = nil
end

local function insert_cancel_escape(bufnr)
  stop_generation(bufnr)
  return '<Esc>'
end

local function build_prompt_lines(source_bufnr, mode, selection)
  local lines = {}
  local filetype = context.get_fence_language(source_bufnr)

  if mode == 'full' then
    local path = vim.api.nvim_buf_get_name(source_bufnr)
    if path == '' then
      path = '[No Name]'
    end

    table.insert(lines, '当前文件: ' .. path)
    context.append_code_block(lines, nil, filetype, context.get_buffer_text(source_bufnr))

    if selection and vim.trim(selection) ~= '' then
      table.insert(lines, '')
      context.append_code_block(lines, '选中文本:', filetype, selection)
    end
  elseif selection and vim.trim(selection) ~= '' then
    context.append_code_block(lines, '选中文本:', filetype, selection)
  end

  if #lines > 0 then
    table.insert(lines, '')
  end

  table.insert(lines, '问题:')
  table.insert(lines, '')

  return lines
end

local function submit(bufnr)
  local state = sessions[bufnr]
  if not state or state.job_id then
    return
  end

  delete_generated(bufnr)

  local prompt_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  while #prompt_lines > 0 and vim.trim(prompt_lines[#prompt_lines]) == '' do
    table.remove(prompt_lines)
  end

  local prompt = table.concat(prompt_lines, '\n')
  if vim.trim(prompt) == '' then
    vim.notify('Prompt is empty.', vim.log.levels.WARN)
    return
  end

  if state.request_finished and state.request_succeeded and state.last_submitted_prompt == prompt then
    return
  end

  state.prompt_end = #prompt_lines
  state.generated_text = '[正在请求中，等待模型响应...]'
  state.status_text = state.generated_text
  state.output_start = state.prompt_end + 2
  state.cancelled = false
  state.error_reported = false
  state.request_finished = false
  state.request_succeeded = false
  state.has_content = false
  state.has_activity = false
  state.last_submitted_prompt = prompt

  vim.api.nvim_buf_set_lines(bufnr, state.prompt_end, -1, false, { '', state.generated_text })

  local job_id, start_error = client.start_stream(config.models.ask, prompt, { temperature = 0.2 }, {
    on_activity = function()
      local active = sessions[bufnr]
      if not active or active.cancelled or active.has_content or active.has_activity then
        return
      end

      active.has_activity = true
      active.status_text = '[模型已响应，正在生成...]'
      active.generated_text = active.status_text
      render_generated(bufnr)
    end,
    on_delta = function(delta)
      local active = sessions[bufnr]
      if not active or active.cancelled then
        return
      end

      if not active.has_content then
        active.generated_text = ''
        active.status_text = ''
        active.has_content = true
      end

      active.generated_text = active.generated_text .. delta
      render_generated(bufnr)
    end,
    on_error = function(message)
      local active = sessions[bufnr]
      if not active or active.cancelled or active.error_reported then
        return
      end

      active.error_reported = true
      active.request_finished = true
      active.request_succeeded = false
      if active.generated_text == '' then
        active.generated_text = '[Error] ' .. message
      else
        active.generated_text = active.generated_text .. '\n\n[Error] ' .. message
      end

      render_generated(bufnr)
    end,
    on_exit = function(code, stderr)
      local active = sessions[bufnr]
      if not active then
        return
      end

      if active.cancelled then
        active.job_id = nil
        active.cancelled = false
        active.request_finished = false
        active.request_succeeded = false
        return
      end

      active.job_id = nil
      if code ~= 0 and vim.trim(active.generated_text) == '' then
        local message = vim.trim(stderr)
        if message == '' then
          message = string.format('LLM request failed with exit code %d.', code)
        end

        active.generated_text = '[Error] ' .. message
        render_generated(bufnr)
        active.request_finished = true
        active.request_succeeded = false
      elseif code == 0 and not active.error_reported and vim.trim(active.generated_text) == '' then
        active.generated_text = '[Error] LLM returned an empty response.'
        render_generated(bufnr)
        active.request_finished = true
        active.request_succeeded = false
      elseif active.error_reported then
        active.request_finished = true
        active.request_succeeded = false
      else
        active.request_finished = true
        active.request_succeeded = true
      end
    end,
  })

  if not job_id then
    delete_generated(bufnr)
    vim.notify(start_error, vim.log.levels.ERROR)
    return
  end

  state.job_id = job_id
end

local function setup_buffer(bufnr)
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = 'markdown'

  vim.keymap.set('n', '<CR>', function()
    submit(bufnr)
  end, { buffer = bufnr, silent = true, desc = 'Submit LLM prompt' })

  vim.keymap.set('n', '<Esc>', function()
    stop_generation(bufnr)
  end, { buffer = bufnr, silent = true, desc = 'Cancel LLM generation' })

  vim.keymap.set('i', '<Esc>', function()
    return insert_cancel_escape(bufnr)
  end, { buffer = bufnr, expr = true, silent = true, desc = 'Cancel LLM generation' })

  vim.keymap.set('i', 'jj', function()
    return insert_cancel_escape(bufnr)
  end, { buffer = bufnr, expr = true, silent = true, desc = 'Cancel LLM generation' })

  vim.keymap.set('n', '<leader>d', function()
    delete_generated(bufnr)
  end, { buffer = bufnr, silent = true, desc = 'Delete AI output' })

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = bufnr,
    callback = function()
      stop_generation(bufnr)
      sessions[bufnr] = nil
    end,
  })
end

function M.open(mode)
  local source_bufnr = vim.api.nvim_get_current_buf()
  local selection = context.get_visual_selection()
  local lines = build_prompt_lines(source_bufnr, mode, selection)

  vim.cmd('botright 15split')

  local win = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, bufnr)
  vim.api.nvim_buf_set_name(bufnr, string.format('llm://%s/%d', mode, bufnr))
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  local state = get_state(bufnr)
  state.generated_text = ''
  state.output_start = nil
  state.prompt_end = nil
  state.job_id = nil
  state.cancelled = false
  state.error_reported = false
  state.request_finished = false
  state.request_succeeded = false
  state.has_content = false
  state.has_activity = false
  state.last_submitted_prompt = nil
  state.status_text = ''

  setup_buffer(bufnr)

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'

  vim.api.nvim_win_set_cursor(win, { #lines, 0 })
  vim.cmd('startinsert!')
end

return M
