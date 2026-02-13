local ns = vim.api.nvim_create_namespace('pinned_selection')
local state = { extmark_id = nil, visible = false }

local function get_visual_selection()
    local sel = {}
    sel.start = vim.fn.getpos("'<'")
    sel.finish = vim.fn.getpos("'>'")
    return sel
end

local function clear_pin()
    if state.extmark_id then
        vim.api.nvim_buf_del_extmark(0, ns, state.extmark_id)
        state.extmark_id = nil
        state.visible = false
    end
end

local function pin_toggle()
    if state.visible then
        clear_pin()
    else
        local sel = get_visual_selection()
        local opts = {
            hl_group = 'Visual',
            end_row = sel.finish,
            end_col = sel.finish,
        }
        state.extmark_id = vim.api.nvim_buf_set_extmark(0, ns, sel.start, sel.finish, opts)
        state.visible = true
    end
end

vim.api.nvim_create_user_command('Pin', function() pin_toggle() end, { nargs = 0, range = true})
