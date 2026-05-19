local config = require('user.llm.config')

local M = {}

local unpack_fn = table.unpack or unpack

local function curl_args(...)
  local args = { 'curl', '--noproxy', '*' }
  vim.list_extend(args, { ... })
  return args
end

local function schedule(cb, ...)
  if not cb then
    return
  end

  local args = { ... }
  vim.schedule(function()
    cb(unpack_fn(args))
  end)
end

local function join_url(base, path)
  if base:sub(-1) == '/' then
    base = base:sub(1, -2)
  end

  if path:sub(1, 1) ~= '/' then
    path = '/' .. path
  end

  return base .. path
end

local function decode_json(text)
  local ok, payload = pcall(vim.json.decode, text)
  if not ok then
    return nil, 'Invalid JSON response from local LLM service.'
  end

  return payload
end

local function extract_error_message(payload)
  if type(payload) ~= 'table' then
    return nil
  end

  if type(payload.error) == 'string' then
    return payload.error
  end

  if type(payload.error) == 'table' then
    return payload.error.message or payload.error.code or vim.inspect(payload.error)
  end

  return nil
end

local function collect_openai_content(content)
  if type(content) == 'string' then
    return content
  end

  if type(content) ~= 'table' then
    return ''
  end

  local parts = {}
  for _, item in ipairs(content) do
    if type(item) == 'string' then
      table.insert(parts, item)
    elseif type(item) == 'table' then
      if item.text then
        table.insert(parts, item.text)
      elseif item.type == 'text' and item.value then
        table.insert(parts, item.value)
      end
    end
  end

  return table.concat(parts)
end

local function extract_response_text(provider, payload)
  if provider.kind == 'ollama' then
    return vim.trim(payload.response or '')
  end

  local choice = payload.choices and payload.choices[1] or nil
  local message = choice and choice.message or nil
  local content = message and message.content or nil
  return vim.trim(collect_openai_content(content))
end

local function resolve_model_ref(model_ref)
  local provider_name, requested_model = model_ref:match('^([^/]+)/(.+)$')
  if not provider_name or not requested_model then
    return nil, nil, nil, string.format('Invalid LLM model ref: %s', model_ref)
  end

  local provider = config.providers[provider_name]
  if not provider then
    return nil, nil, nil, string.format('Unknown LLM provider: %s', provider_name)
  end

  return provider_name, provider, requested_model
end

local function build_request(provider, model_name, prompt, opts)
  opts = opts or {}

  if provider.kind == 'ollama' then
    return join_url(provider.base_url, '/api/generate'), {
      model = model_name,
      prompt = prompt,
      stream = opts.stream == true,
      options = {
        temperature = opts.temperature or 0,
      },
    }
  end

  local payload = {
    model = model_name,
    messages = {
      {
        role = 'user',
        content = prompt,
      },
    },
    stream = opts.stream == true,
    temperature = opts.temperature or 0,
  }

  if opts.max_tokens then
    payload.max_tokens = opts.max_tokens
  end

  return join_url(provider.base_url, '/chat/completions'), payload
end

function M.request(model_ref, prompt, opts, callback)
  opts = opts or {}

  local provider_name, provider, model_name, resolve_error = resolve_model_ref(model_ref)
  if not provider then
    schedule(callback, nil, resolve_error)
    return
  end

  local metadata = {
    provider = provider_name,
    model = model_name,
  }

  local endpoint, payload = build_request(provider, model_name, prompt, opts)
  vim.system(curl_args(
    '-sS',
    '-X',
    'POST',
    endpoint,
    '-H',
    'Content-Type: application/json',
    '-d',
    vim.json.encode(payload)
  ), { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local message = vim.trim(result.stderr ~= '' and result.stderr or result.stdout)
        if message == '' then
          message = string.format('Failed to connect to provider "%s".', provider_name)
        end

        callback(nil, message, metadata)
        return
      end

      local response, decode_error = decode_json(result.stdout)
      if not response then
        callback(nil, decode_error, metadata)
        return
      end

      local service_error = extract_error_message(response)
      if service_error then
        callback(nil, service_error, metadata)
        return
      end

      local text = extract_response_text(provider, response)
      if text == '' then
        callback(nil, string.format('Provider "%s" returned an empty response.', provider_name), metadata)
        return
      end

      callback(text, nil, metadata)
    end)
  end)
end

function M.start_stream(model_ref, prompt, opts, callbacks)
  opts = opts or {}
  callbacks = callbacks or {}

  local provider_name, provider, model_name, resolve_error = resolve_model_ref(model_ref)
  if not provider then
    return nil, resolve_error
  end

  local metadata = {
    provider = provider_name,
    model = model_name,
  }

  local endpoint, payload = build_request(provider, model_name, prompt, vim.tbl_extend('force', opts, { stream = true }))
  local stderr_chunks = {}
  local stdout_pending = ''

  local function process_stream_line(line)
    line = vim.trim(line)
    if line == '' then
      return
    end

    if provider.kind == 'openai' then
      if not vim.startswith(line, 'data:') then
        return
      end

      local body = vim.trim(line:sub(6))
      if body == '[DONE]' then
        return
      end

      local response, decode_error = decode_json(body)
      if not response then
        schedule(callbacks.on_error, decode_error, metadata)
        return
      end

      local service_error = extract_error_message(response)
      if service_error then
        schedule(callbacks.on_error, service_error, metadata)
        return
      end

      local choice = response.choices and response.choices[1] or nil
      local reasoning = choice and choice.delta and choice.delta.reasoning_content or ''
      if reasoning ~= '' then
        schedule(callbacks.on_activity, metadata)
      end

      local delta = choice and choice.delta and collect_openai_content(choice.delta.content) or ''
      if delta ~= '' then
        schedule(callbacks.on_activity, metadata)
        schedule(callbacks.on_delta, delta, metadata)
      end

      return
    end

    local response, decode_error = decode_json(line)
    if not response then
      schedule(callbacks.on_error, decode_error, metadata)
      return
    end

    local service_error = extract_error_message(response)
    if service_error then
      schedule(callbacks.on_error, service_error, metadata)
      return
    end

    local delta = response.response or ''
    if delta ~= '' then
      schedule(callbacks.on_activity, metadata)
      schedule(callbacks.on_delta, delta, metadata)
    end
  end

  local function consume_stdout(data)
    if not data then
      return
    end

    for index, chunk in ipairs(data) do
      chunk = chunk or ''
      if index == #data then
        stdout_pending = stdout_pending .. chunk
      else
        process_stream_line(stdout_pending .. chunk)
        stdout_pending = ''
      end
    end
  end

  local job_id = vim.fn.jobstart(curl_args(
    '-sS',
    '-N',
    '-X',
    'POST',
    endpoint,
    '-H',
    'Content-Type: application/json',
    '-d',
    vim.json.encode(payload)
  ), {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      consume_stdout(data)
    end,
    on_stderr = function(_, data)
      if not data then
        return
      end

      for _, chunk in ipairs(data) do
        if chunk and chunk ~= '' then
          table.insert(stderr_chunks, chunk)
        end
      end
    end,
    on_exit = function(_, code)
      if stdout_pending ~= '' then
        process_stream_line(stdout_pending)
        stdout_pending = ''
      end

      schedule(callbacks.on_exit, code, table.concat(stderr_chunks, '\n'), metadata)
    end,
  })

  if job_id <= 0 then
    return nil, string.format('Failed to start streaming request for provider "%s".', provider_name)
  end

  return job_id, nil, metadata
end

function M.stop(job_id)
  if job_id then
    vim.fn.jobstop(job_id)
  end
end

return M
