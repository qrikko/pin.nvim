require('pin').setup()

vim.api.nvim_create_user_command('PinTS', function()
    require('pin').pin_ts_node()
end, { desc = "Pin the tree-sitter node at the cursor" })

vim.api.nvim_create_user_command('PinToggle', function()
    require('pin').pin_toggle()
end, { desc = "Pin the node at the cursor, or unpin the pin at the cursor" })

vim.api.nvim_create_user_command('PinUnpin', function()
    local pin = require('pin')
    local ctx = pin.context()
    local index = pin.pin_at_lnum(ctx.buf, ctx.lnum)
    if not index then
        vim.notify("No pin at cursor")
        return
    end
    pin.pin_remove(index)
end, { desc = "Remove the pin at the cursor" })

vim.api.nvim_create_user_command('PinVisual', function()
    require('pin').pin_visual_selection()
end, { range = true })

vim.api.nvim_create_user_command('PinPop', function()
    require('pin').pin_remove()
end, { desc = "Remove the pin at the cursor, or the last pin" })

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
