local ns = vim.api.nvim_create_namespace('pinned_selection')
local state = { extmark_id = nil, visible = false }

local function get_visual_selection()
    local start = vim.fn.getpos("'<'")
    local finish = vim.fn.getpos("'>'")

    return {
        start_line  = start[2] -1,
        start_col   = start[2] -1,
        end_line    = start[2] -1,
        end_col     = start[2] -1,
    }
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
        state.extmark_id = vim.api.nvim_buf_set_extmark(0, ns, sel.start_line, sel.start_col, {
            end_row = sel.end_line,
            end_col = sel.end_col,
            hl_group = "Visual",
        })
    end
end

vim.api.nvim_create_user_command('Pin', function() pin_toggle() end, { nargs = 0, range = true})
