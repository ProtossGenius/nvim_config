local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

support.reset({ '<hello></hello>' }, 'xml', 'xml')
support.set_cursor_on_substring(1, 'hello', 1)
vim.cmd('doautocmd CursorMoved')
support.feed('ciwworld<Esc>')
support.expect_equal('xml paired tags rename together', support.current_lines(), { '<world></world>' })

support.reset({ '<hello/>' }, 'xml', 'xml')
support.set_cursor_on_substring(1, 'hello', 1)
vim.cmd('doautocmd CursorMoved')
support.feed('ciwworld<Esc>')
support.expect_equal('xml self closing tag stays self closing', support.current_lines(), { '<world/>' })

support.reset({ '<hello></world>' }, 'xml', 'xml')
support.set_cursor_on_substring(1, 'hello', 1)
vim.cmd('doautocmd CursorMoved')
support.feed('ciwplanet<Esc>')
support.expect_equal('xml mismatched tags are not force synced', support.current_lines(), { '<planet></world>' })

support.expect_true('xml emmet install is buffer local', vim.fn.maparg(',,', 'i', false, true).lhs ~= nil)

support.flush()
