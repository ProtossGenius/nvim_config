-- [[ user.keymaps ]]
-- Keymaps

local opts = { noremap = true, silent = true }
local keymap = vim.keymap.set
local file_actions = require('user.file_actions')
local text_move = require('user.text_move')

local function leader_map(mode, lhs, rhs, desc)
  keymap(mode, lhs, rhs, vim.tbl_extend('force', opts, { desc = desc }))
end

local function expr_map(mode, lhs, rhs, desc)
  keymap(mode, lhs, rhs, vim.tbl_extend('force', opts, { expr = true, desc = desc }))
end

local function toggle_comment_current()
  require('user.comment').toggle_current()
end

-- Insert Mode
keymap('i', 'jj', '<ESC>', opts)
-- 在终端模式下，将 jj 映射为退出终端模式
vim.api.nvim_set_keymap('t', 'jj', '<C-\\><C-n>', { noremap = true, silent = true, desc = 'Exit terminal mode to Normal' })
-- Normal Mode

-- Normal mode Chinese colon '：' auto-switch to English input method
keymap('n', '：', function()
  if vim.fn.executable('im-select') == 1 then
    vim.fn.system({ 'im-select', vim.g.mac_english_input_source or 'com.apple.keylayout.ABC' })
  elseif vim.fn.executable('fcitx-remote') == 1 then
    vim.fn.system('fcitx-remote -c')
  end
  vim.api.nvim_feedkeys(':', 'n', true)
end, { desc = 'Switch to English and enter command mode' })
-- Save buffer
keymap({ 'i', 'n', 'v' }, '<C-s>', '<cmd>w<cr><esc>', { desc = 'Save file' })
leader_map('n', '<leader>fs', '<cmd>w<cr>', 'Save file')
keymap('n', '<C-_>', toggle_comment_current, { desc = 'Toggle comment' })
keymap('n', '<C-/>', toggle_comment_current, { desc = 'Toggle comment' })
keymap('x', '<C-_>', '<Esc><Cmd>lua require("user.comment").toggle_visual()<CR>', { desc = 'Toggle comment selection' })
keymap('x', '<C-/>', '<Esc><Cmd>lua require("user.comment").toggle_visual()<CR>', { desc = 'Toggle comment selection' })

-- File Explorer
-- keymap('n', '-', '<cmd>Dirvish<cr>', { desc = 'Open Dirvish' })

-- Window Navigation
keymap('n', '<leader><Right>', '<C-w>l', { desc = 'Move to right window' })
keymap('n', '<leader><Left>', '<C-w>h', { desc = 'Move to left window' })
keymap('n', '<leader><Up>', '<C-w>k', { desc = 'Move to upper window' })
keymap('n', '<leader><Down>', '<C-w>j', { desc = 'Move to lower window' })
keymap('n', '<leader>l', '<C-w>l', { desc = 'Move to right window' })
keymap('n', '<leader>h', '<C-w>h', { desc = 'Move to left window' })
keymap('n', '<leader>k', '<C-w>k', { desc = 'Move to upper window' })
keymap('n', '<leader>j', '<C-w>j', { desc = 'Move to lower window' })
keymap('n', '<leader>sv', '<cmd>vsplit<cr>', { desc = 'Split window vertically' })
leader_map('n', '<leader>wh', '<C-w>h', 'Move to left window')
leader_map('n', '<leader>wj', '<C-w>j', 'Move to lower window')
leader_map('n', '<leader>wk', '<C-w>k', 'Move to upper window')
leader_map('n', '<leader>wl', '<C-w>l', 'Move to right window')
leader_map('n', '<leader>wv', '<cmd>vsplit<cr>', 'Split window vertically')
keymap('n', '<M-Left>', '<C-w>h', { desc = 'Move to left window' })
keymap('n', '<M-h>', '<C-w>h', { desc = 'Move to left window' })
keymap('n', '<M-Down>', '<C-w>j', { desc = 'Move to lower window' })
keymap('n', '<M-Up>', '<C-w>k', { desc = 'Move to upper window' })
keymap('n', '<M-Right>', '<C-w>l', { desc = 'Move to right window' })
keymap('n', '<M-l>', '<C-w>l', { desc = 'Move to right window' })
keymap('n', '<M-j>', '<C-w>j', { desc = 'Move to lower window' })
keymap('n', '<M-k>', '<C-w>k', { desc = 'Move to upper window' })
keymap('t', '<M-Left>', '<C-\\><C-n><C-w>h', { desc = 'Move to left window' })
keymap('t', '<M-h>', '<C-\\><C-n><C-w>h', { desc = 'Move to left window' })
keymap('t', '<M-Down>', '<C-\\><C-n><C-w>j', { desc = 'Move to lower window' })
keymap('t', '<M-Up>', '<C-\\><C-n><C-w>k', { desc = 'Move to upper window' })
keymap('t', '<M-Right>', '<C-\\><C-n><C-w>l', { desc = 'Move to right window' })
keymap('t', '<M-l>', '<C-\\><C-n><C-w>l', { desc = 'Move to right window' })
keymap('t', '<M-j>', '<C-\\><C-n><C-w>j', { desc = 'Move to lower window' })
keymap('t', '<M-k>', '<C-\\><C-n><C-w>k', { desc = 'Move to upper window' })

-- Diagnostics (replaces ALE bindings)
keymap({'n', 'i'}, '<M-n>', vim.diagnostic.goto_next, { desc = 'Next diagnostic' })
keymap({'n', 'i'}, '<M-p>', vim.diagnostic.goto_prev, { desc = 'Previous diagnostic' })
keymap('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Show diagnostic error' })
leader_map('n', '<leader>xn', vim.diagnostic.goto_next, 'Next diagnostic')
leader_map('n', '<leader>xp', vim.diagnostic.goto_prev, 'Previous diagnostic')
leader_map('n', '<leader>xe', vim.diagnostic.open_float, 'Show diagnostic error')

-- Enter diagnostic float window (press again or use <leader>xf to focus)
leader_map('n', '<leader>xf', function()
  local _, winid = vim.diagnostic.open_float({ focus = true })
  if winid then
    vim.api.nvim_set_current_win(winid)
  end
end, 'Focus diagnostic float')

-- Copy all diagnostics on current line to system clipboard
leader_map('n', '<leader>xy', function()
  local diagnostics = vim.diagnostic.get(0, { lnum = vim.api.nvim_win_get_cursor(0)[1] - 1 })
  if #diagnostics == 0 then
    vim.notify('No diagnostics on this line', vim.log.levels.INFO)
    return
  end
  local lines = {}
  for _, d in ipairs(diagnostics) do
    local severity = vim.diagnostic.severity[d.severity] or 'UNKNOWN'
    table.insert(lines, string.format('[%s] %s', severity, d.message))
  end
  local text = table.concat(lines, '\n')
  vim.fn.setreg('+', text)
  vim.notify(string.format('Copied %d diagnostic(s) to clipboard', #diagnostics), vim.log.levels.INFO)
end, 'Copy line diagnostics to clipboard')

-- Git Changes
keymap('n', ']c', '<cmd>Gitsigns next_hunk<cr>', { desc = 'Next Git change' })
keymap('n', '[c', '<cmd>Gitsigns prev_hunk<cr>', { desc = 'Previous Git change' })
leader_map('n', '<leader>gn', '<cmd>Gitsigns next_hunk<cr>', 'Next Git change')
leader_map('n', '<leader>gp', '<cmd>Gitsigns prev_hunk<cr>', 'Previous Git change')

-- Telescope (replaces LeaderF bindings)
keymap('n', '<C-n>', '<cmd>Telescope oldfiles<cr>', { desc = 'Find recent files' })
keymap('n', '<leader>p', '<cmd>Telescope projects<cr>', { desc = 'Find projects' })
keymap('n', '<leader>ds', '<cmd>Telescope lsp_document_symbols<cr>', { desc = 'Document symbols' })
keymap('n', '<leader>ts', '<cmd>Telescope tags<cr>', { desc = 'Find tags' })
leader_map('n', '<leader>fa', function()
  require('telescope.builtin').find_files({
    cwd = _G.initial_cwd or vim.fn.getcwd(),
    hidden = true,
    no_ignore = true,
    no_ignore_parent = true,
    follow = true,
  })
end, 'Find files (including ignored)')
leader_map('n', '<leader>fb', '<cmd>Telescope buffers<cr>', 'Find buffers')
leader_map('n', '<leader>fg', function()
  require('telescope.builtin').live_grep({
    cwd = _G.initial_cwd or vim.fn.getcwd(),
  })
end, 'Live Grep')
leader_map('n', '<leader>fr', '<cmd>Telescope oldfiles<cr>', 'Find recent files')
leader_map('n', '<leader>ft', '<cmd>Telescope tags<cr>', 'Find tags')
leader_map('n', '<leader>pp', '<cmd>Telescope projects<cr>', 'Find projects')
leader_map('n', '<leader>br', file_actions.rename_current_buffer, 'Buffer: Rename file')
leader_map('n', '<leader>bd', file_actions.delete_current_buffer_file, 'Buffer: Delete file from disk')

-- Terminal
-- Terminal toggle (Alt-t)
local function toggle_terminal()
  local terminal_buffers = {}
  local visible_terminal_winid = nil

  -- Find all terminal buffers and check for visible terminals
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_option(bufnr, 'buftype') == 'terminal' then
      table.insert(terminal_buffers, bufnr)
      -- Check if this terminal buffer is currently visible in any window
      for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(winid) == bufnr then
          visible_terminal_winid = winid
          break
        end
      end
    end
  end

  if visible_terminal_winid then
    -- If a terminal is visible, hide it (close its window)
    vim.api.nvim_win_close(visible_terminal_winid, true)
  else
    local win_opts = {
      relative = 'editor',
      width = vim.o.columns,
      height = vim.o.lines - 2,
      col = 0,
      row = 0,
      style = 'minimal',
      border = 'none',
      zindex = 50,
    }

    -- ALWAYS use the immutable initial starting directory as the terminal directory
    local target_dir = _G.initial_cwd or vim.fn.getcwd()
    target_dir = vim.fs.normalize(target_dir)

    -- Find an existing terminal buffer for target_dir
    local matched_buf = nil
    for _, bufnr in ipairs(terminal_buffers) do
      local ok, term_dir = pcall(vim.api.nvim_buf_get_var, bufnr, 'terminal_dir')
      if ok and term_dir == target_dir then
        matched_buf = bufnr
        break
      end
    end

    if matched_buf then
      vim.api.nvim_open_win(matched_buf, true, win_opts)
      vim.cmd('startinsert!') -- Enter insert mode automatically
    else
      -- Create a new terminal in target_dir
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_open_win(buf, true, win_opts)
      vim.fn.termopen(vim.o.shell, { cwd = target_dir })
      vim.api.nvim_buf_set_var(buf, 'terminal_dir', target_dir)
      vim.cmd('startinsert!') -- Enter insert mode automatically
    end
  end
end

keymap({'n', 'i', 'v', 't'}, '<M-t>', toggle_terminal, { desc = 'Toggle terminal' })
leader_map('n', '<leader>tt', toggle_terminal, 'Toggle terminal')

-- Move lines / selections
keymap('n', '<M-J>', text_move.move_line_down, { desc = 'Move line down' })
keymap('n', '<M-K>', text_move.move_line_up, { desc = 'Move line up' })
keymap('n', '<M-S-Down>', text_move.move_line_down, { desc = 'Move line down' })
keymap('n', '<M-S-Up>', text_move.move_line_up, { desc = 'Move line up' })
keymap('x', '<M-J>', text_move.move_selection_down, { desc = 'Move selection down' })
keymap('x', '<M-K>', text_move.move_selection_up, { desc = 'Move selection up' })
keymap('x', '<M-S-Down>', text_move.move_selection_down, { desc = 'Move selection down' })
keymap('x', '<M-S-Up>', text_move.move_selection_up, { desc = 'Move selection up' })
keymap('i', '<M-J>', text_move.move_insert_line_down, { desc = 'Move line down' })
keymap('i', '<M-K>', text_move.move_insert_line_up, { desc = 'Move line up' })
keymap('i', '<M-S-Down>', text_move.move_insert_line_down, { desc = 'Move line down' })
keymap('i', '<M-S-Up>', text_move.move_insert_line_up, { desc = 'Move line up' })

-- Better movement
expr_map({ 'n', 'x', 'o' }, 'j', "v:count == 0 ? 'gj' : 'j'", 'Down by display line')
expr_map({ 'n', 'x', 'o' }, 'k', "v:count == 0 ? 'gk' : 'k'", 'Up by display line')
expr_map({ 'n', 'x', 'o' }, '<Down>', "v:count == 0 ? 'gj' : 'j'", 'Down by display line')
expr_map({ 'n', 'x', 'o' }, '<Up>', "v:count == 0 ? 'gk' : 'k'", 'Up by display line')

-- Compile and Run commands
-- Helper function to run commands in a terminal
local function term_exec_cwd()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if vim.bo[bufnr].filetype == 'dirvish' and bufname ~= '' then
    return vim.fn.fnamemodify(bufname, ':p')
  end

  return vim.fn.getcwd()
end

local function term_exec(cmd)
  vim.cmd('wa')
  vim.cmd('enew')
  vim.fn.termopen(cmd, { cwd = term_exec_cwd() })
  vim.cmd('startinsert')
end
keymap('v', '<C-c>', 'y')
keymap('n', '<S-f>', function() require('user.jump').jump_current_line() end, { desc = 'Jump stack/reference or fallback to gF' })
keymap('n', '<F5>', function() term_exec('make qrun') end, { desc = 'Make qrun' })
keymap('n', '<F6>', function() term_exec('make') end, { desc = 'Make' })
keymap('n', '<F8>', function() term_exec('make tests') end, { desc = 'Make tests' })
keymap('n', '<F9>', function() term_exec('make debug') end, { desc = 'Make debug' })
leader_map('n', '<leader>mr', function() term_exec('make qrun') end, 'Make qrun')
leader_map('n', '<leader>mm', function() term_exec('make') end, 'Make')
leader_map('n', '<leader>mt', function() term_exec('make tests') end, 'Make tests')
leader_map('n', '<leader>md', function() term_exec('make debug') end, 'Make debug')

leader_map('n', '<leader>of', function() require('user.jump').prompt_jump() end, 'Open exact file/reference')
leader_map('n', '<leader>or', function() require('user.jump').copy_reference() end, 'Copy reference')
leader_map('n', '<leader>lv', function() require('user.scratchpad').open_scratchpad() end, 'Scratchpad: Open floating scratchpad')

-- Aerial (Code Outline)
keymap('n', '<leader>a', '<cmd>AerialToggle! left<cr>', { desc = 'Toggle Aerial outline' })
leader_map('n', '<leader>oa', '<cmd>AerialToggle! left<cr>', 'Toggle Aerial outline')

local function llm_translate()
  require('user.translate').translate()
end

local function llm_ask_with_file()
  require('user.llm.ask').open('full')
end

local function llm_ask_with_selection()
  require('user.llm.ask').open('selection')
end

keymap({ 'n', 'x' }, '<leader>Lt', llm_translate, { desc = 'LLM: Translate' })
keymap({ 'n', 'x' }, '<leader>L/', llm_ask_with_file, { desc = 'LLM: Ask with file context' })
keymap({ 'n', 'x' }, '<leader>L>', llm_ask_with_selection, { desc = 'LLM: Ask with selection' })
keymap({ 'n', 'x' }, '<leader>L?', llm_ask_with_selection, { desc = 'LLM: Ask with selection' })
keymap({ 'n', 'x' }, '<leader>/', llm_ask_with_file, { desc = 'Ask with file context' })
keymap({ 'n', 'x' }, '<leader>>', llm_ask_with_selection, { desc = 'Ask with selection' })
keymap({ 'n', 'x' }, '<leader>ot', llm_translate, { desc = 'Translate with LLM' })

-- Go plugin mappings (kept for compatibility if vim-go is enabled again)
keymap('n', '<leader>gs', '<Plug>(go-implements)', { desc = 'Go implements' })
keymap('n', '<leader>gi', '<Plug>(go-info)', { desc = 'Go info' })
keymap('n', '<leader>gr', '<Plug>(go-run)', { desc = 'Go run' })
keymap('n', '<leader>gb', '<Plug>(go-build)', { desc = 'Go build' })
keymap('n', '<leader>gt', '<Plug>(go-test)', { desc = 'Go test' })
keymap('n', '<leader>rn', '<Plug>(go-rename)', { desc = 'Go rename' })

-- C/C++ Macro Expansion
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "c", "cpp" },
  callback = function()
    if require('user.util').is_cpp_project(0) then
      vim.keymap.set('n', '<M-y>', function()
        require('user.util').toggle_header_source()
      end, { buffer = true, desc = 'Toggle header/source' })
      vim.keymap.set('n', '<leader>oh', function()
        require('user.util').toggle_header_source()
      end, { buffer = true, desc = 'Toggle header/source' })
    end

    vim.keymap.set('i', ',mm', function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local line = vim.api.nvim_get_current_line()
      if cursor[2] >= 3 then
        local new_line = line:sub(1, cursor[2] - 3) .. line:sub(cursor[2] + 1)
        vim.api.nvim_set_current_line(new_line)
        vim.api.nvim_win_set_cursor(0, { cursor[1], cursor[2] - 3 })
      end
      require('user.util').expand_macro()
    end, { buffer = true, desc = 'Expand macro' })

    vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, { desc = "LSP 重命名" })
    vim.keymap.set('n', ',mm', function()
      require('user.util').expand_macro()
    end, { buffer = true, desc = 'Expand macro' })
  end,
})

-- Bind standard nvim-dap API keymaps directly
local function dap_map(mode, lhs, rhs, desc)
  local wrapped_rhs = rhs
  if type(rhs) == 'function' then
    wrapped_rhs = function(...)
      pcall(function()
        require('user.audit').log_dap_action('User triggered keymap: ' .. lhs, { desc = desc })
      end)
      -- Save step/continue debugging actions to _G.last_dap_action
      if lhs == '<leader>dn' or lhs == '<leader>di' or lhs == '<leader>do' or lhs == '<leader>dc' then
        _G.last_dap_action = rhs
      end
      return rhs(...)
    end
  end
  vim.keymap.set(mode, lhs, wrapped_rhs, { noremap = true, silent = true, desc = desc })
end

-- DAP Repeat last action with Enter (<CR>)
keymap('n', '<CR>', function()
  local buftype = vim.bo.buftype
  local filetype = vim.bo.filetype

  -- Only repeat last step if we are in a normal file/buffer
  if buftype ~= '' then
    return '<CR>'
  end

  -- Skip if we are in any DAP UI or float windows
  if filetype:match('^dap') then
    return '<CR>'
  end

  local dap_ok, dap = pcall(require, 'dap')
  if dap_ok and dap.session() and _G.last_dap_action then
    _G.last_dap_action()
    return ''
  else
    return '<CR>'
  end
end, { expr = true, noremap = true, silent = true, desc = 'DAP: Repeat last debug step or standard Enter' })

dap_map('n', '<leader>db', function() require('dap').toggle_breakpoint() end, 'Debug: Toggle breakpoint')
dap_map('n', '<leader>dB', function()
  local cond = vim.fn.input('Breakpoint condition: ')
  if cond and cond ~= '' then
    require('dap').set_breakpoint(cond)
  end
end, 'Debug: Set conditional breakpoint')
dap_map('n', '<leader>dc', function() require('dap').continue() end, 'Debug: Continue / Start')
dap_map('n', '<leader>dn', function() require('dap').step_over() end, 'Debug: Step over / Next')
dap_map('n', '<leader>di', function() require('dap').step_into() end, 'Debug: Step into')
dap_map('n', '<leader>do', function() require('dap').step_out() end, 'Debug: Step out')
dap_map('n', '<leader>dr', function() require('dap').repl.open() end, 'Debug: Open REPL console')
dap_map('n', '<leader>da', '<cmd>DapAttach<cr>', 'Debug: Attach debugger (TCP port / PID)')
dap_map('n', '<leader>dq', '<cmd>DapTerminate<cr>', 'Debug: Terminate session')

-- Lightweight standard sidebar widgets built into nvim-dap
dap_map('n', '<leader>dl', function()
  require('dap.ui.widgets').sidebar(require('dap.ui.widgets').scopes).open()
end, 'Debug: Show variables/scopes sidebar')

dap_map('n', '<leader>dt', function()
  require('dap.ui.widgets').sidebar(require('dap.ui.widgets').frames).open()
end, 'Debug: Show stack frames sidebar')

dap_map('n', '<leader>Dc', '<cmd>DebugStart<cr>', 'Debug: Start session from local config')
dap_map('n', '<leader>De', '<cmd>DebugConfigEdit<cr>', 'Debug: Create or edit local configs')



-- Dirvish explorer helpers
local function dirvish_run_command()
  local file_path = vim.fn.getline('.')
  if file_path == '' then return end
  
  local clean_path = file_path
  if clean_path:sub(-1) == '/' then
    clean_path = clean_path:sub(1, -2)
  end

  local cmd = vim.fn.input({
    prompt = 'Shell command: ',
    default = '',
    completion = 'shellcmd',
  })
  
  if cmd == '' then return end
  
  local final_cmd
  if cmd:find('%%') then
    final_cmd = cmd:gsub('%%', vim.fn.shellescape(clean_path))
  else
    final_cmd = cmd .. ' ' .. vim.fn.shellescape(clean_path)
  end
  
  local dir = vim.fn.expand('%:p')
  
  vim.cmd('split')
  local new_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(new_buf)
  vim.fn.termopen(final_cmd, { cwd = dir })
  vim.cmd('startinsert')
end

local function dirvish_rename()
  local old_path = vim.fn.getline('.')
  if old_path == '' then return end

  local clean_old_path = old_path:sub(-1) == '/' and old_path:sub(1, -2) or old_path
  file_actions.rename_path(clean_old_path, {
    refresh = function()
      vim.cmd('Dirvish %')
    end,
  })
end

local function dirvish_delete()
  local target_path = vim.fn.getline('.')
  if target_path == '' then return end

  local clean_target_path = target_path:sub(-1) == '/' and target_path:sub(1, -2) or target_path
  file_actions.delete_path(clean_target_path, {
    refresh = function()
      vim.cmd('Dirvish %')
    end,
  })
end

local function dirvish_create()
  local function is_absolute_path(path)
    return path:match('^/') ~= nil
      or path:match('^%a:[/\\]') ~= nil
      or path:match('^//') ~= nil
      or path:match('^\\\\') ~= nil
  end

  local dir = vim.fs.normalize(vim.fn.expand('%:p'))
  local default_name = vim.fn.input('Create file: ', '', 'file')
  if default_name == '' then
    return
  end

  local target_path = default_name
  if not is_absolute_path(target_path) then
    target_path = vim.fs.joinpath(dir, target_path)
  end

  file_actions.create_path(target_path, {
    refresh = function()
      vim.cmd('Dirvish ' .. vim.fn.fnameescape(dir))
    end,
    open_after_create = true,
  })
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "dirvish",
  callback = function()
    local bufnr = vim.api.nvim_get_current_buf()
    vim.keymap.set('n', 'a', dirvish_create, { buffer = bufnr, silent = true, desc = 'Create file' })
    vim.keymap.set('n', 'x', dirvish_run_command, { buffer = bufnr, silent = true, desc = 'Run shell command' })
    vim.keymap.set('n', '!', dirvish_run_command, { buffer = bufnr, silent = true, desc = 'Run shell command' })
    vim.keymap.set('n', 'r', dirvish_rename, { buffer = bufnr, silent = true, desc = 'Rename file' })
    vim.keymap.set('n', 'D', dirvish_delete, { buffer = bufnr, silent = true, desc = 'Delete file from disk' })
    vim.keymap.set('n', '<leader>ba', dirvish_create, { buffer = bufnr, silent = true, desc = 'Buffer: Create file' })
    vim.keymap.set('n', '<leader>bx', dirvish_run_command, { buffer = bufnr, silent = true, desc = 'Buffer: Run shell command on selected file' })
    vim.keymap.set('n', '<leader>br', dirvish_rename, { buffer = bufnr, silent = true, desc = 'Buffer: Rename selected file' })
    vim.keymap.set('n', '<leader>bd', dirvish_delete, { buffer = bufnr, silent = true, desc = 'Buffer: Delete selected file from disk' })
  end,
})

-- Terminal Buffer <CR> Rerun last command mapping
vim.api.nvim_create_autocmd("TermOpen", {
  group = vim.api.nvim_create_augroup("UserTerminalCR", { clear = true }),
  callback = function()
    local bufnr = vim.api.nvim_get_current_buf()
    vim.keymap.set('n', '<CR>', 'i<Up><CR>', { buffer = bufnr, noremap = true, silent = true, desc = 'Repeat last terminal command' })
  end
})

-- DAP UI: Jump to location under cursor on Enter (<CR>)
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "dapui_stacks", "dapui_breakpoints" },
  callback = function()
    local bufnr = vim.api.nvim_get_current_buf()
    vim.keymap.set('n', '<CR>', 'o', { buffer = bufnr, remap = true, silent = true, desc = 'DAP UI: Jump to location on Enter' })
  end
})
