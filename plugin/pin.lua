require('pin').setup()

vim.api.nvim_create_user_command('PinTS', function()
    require('pin').pin_ts_node()
end, {})

vim.api.nvim_create_user_command('PinVisual', function()
    require('pin').pin_visual_selection()
end, { range = true })

vim.api.nvim_create_user_command('PinPop', function()
    require('pin').pin_remove()
end, {})

vim.api.nvim_create_user_command('PinRemove', function()
    require('pin').pin_remove_interactive()
end, { desc = "Remove pin by id" })

vim.api.nvim_create_user_command('PinClear', function()
    require('pin').clear_pin()
end, {})

vim.api.nvim_create_user_command('PinFocusNext', function()
    require('pin').pin_focus_next()
end, {})

vim.api.nvim_create_user_command('PinFocusPrev', function()
    require('pin').pin_focus_prev()
end, {})

vim.api.nvim_create_user_command('PinFocusVisual', function()
    require('pin').pin_focus_interactive()
end, {})
