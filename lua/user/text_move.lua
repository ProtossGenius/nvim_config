local M = {}

function M.move_line_down()
  vim.cmd('move .+1')
  vim.cmd('normal! ==')
end

function M.move_line_up()
  vim.cmd('move .-2')
  vim.cmd('normal! ==')
end

function M.move_selection_down()
  vim.cmd("move '>+1")
  vim.cmd('normal! gv=gv')
end

function M.move_selection_up()
  vim.cmd("move '<-2")
  vim.cmd('normal! gv=gv')
end

function M.move_insert_line_down()
  M.move_line_down()
  vim.cmd('startinsert')
end

function M.move_insert_line_up()
  M.move_line_up()
  vim.cmd('startinsert')
end

return M
