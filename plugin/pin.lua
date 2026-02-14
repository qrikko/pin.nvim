vim.api.nvim_create_user_command('PinTS', function()
    require('pin').pin_ts_node()
end, {})

vim.api.nvim_create_user_command('PinVisual', function()
    require('pin').pin_visual_selection()
end, { range = true })

vim.api.nvim_create_user_command('PinClear', function()
    require('pin').clear_pin()
end, {})
