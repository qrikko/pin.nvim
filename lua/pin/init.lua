local M = {}
local ns_id = vim.api.nvim_create_namespace("PinPlugin")
local did_setup = false

M.config = {
    winblend = 0,
    border = 'single',
    max_height = 15,
    keymaps = {
        pin_ts              = '<leader>sp',
        pin_visual          = '<leader>sp',
        clear_all_pins      = '<leader>sc'
    }
}

local function get_layout_details()
    local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
    local gutter_w = info.textoff
    local win_w = vim.api.nvim_win_get_width(0)
    local available_w = win_w - gutter_w - 1
    return gutter_w, available_w
end

local function update_pin_position()
    if not M.active_pin or not vim.api.nvim_win_is_valid(M.active_pin.win_id) then return end

    local current_win = 0
    local current_buf = vim.api.nvim_get_current_buf()

    -- Hide the pin if we switch to a different buffer
    if current_buf ~= M.active_pin.source_buf then
        vim.api.nvim_win_set_config(
            M.active_pin.win_id, {
                relative = 'editor',
                row = 1000,
                col = 1000
            }
        ) -- Move off-screen
        return
    end

    -- Get the current location of our pinned code via the Extmark
    local mark = vim.api.nvim_buf_get_extmark_by_id(M.active_pin.source_buf, ns_id, M.active_pin.mark_id, {})
    local mark_line = mark[1] + 1 -- convert to 1-indexed

    local top_visible_line = vim.fn.line("w0")
    local bot_visible_line = vim.fn.line("w$")

    local final_row = 0

    if mark_line < top_visible_line then
        -- It's above us: Stick to top
        final_row = 0
    elseif mark_line > bot_visible_line then
        -- It's below us: Stick to bottom (accounting for pin height)
        final_row = vim.api.nvim_win_get_height(current_win) - M.active_pin.height - 2
    else
        -- It's visible: Move it to its natural position relative to the top of the window
        final_row = mark_line - top_visible_line
    end

    -- Inside update_pin_position:
    local gutter_w, usable_width = get_layout_details()

    vim.api.nvim_win_set_config(M.active_pin.win_id, {
        relative = 'win',
        win = current_win,
        row = final_row,
        col = gutter_w,
        width = usable_width -- Keep the width consistent
    })
end


function M.setup(user_config)
    M.config = vim.tbl_deep_extend("force", M.config, user_config or {})

    if M.config.keymaps then
        vim.keymap.set('n', M.config.keymaps.pin_ts, ':PinTS<CR>', {desc = "Pin TS Node"})
        vim.keymap.set('v', M.config.keymaps.pin_visual, ':PinVisual<CR>', {desc = "Pin Visual Selection"})
        vim.keymap.set({'n','v'}, M.config.keymaps.clear_all_pins, ':PinClear<CR>', {desc = "Clear ALL Pins"})
    end

    local group = vim.api.nvim_create_augroup("PinScrollLogic", {clear = true})

    vim.api.nvim_create_autocmd({"WinScrolled", "CursorMoved"}, {
        group = group,
        callback = function() update_pin_position() end
    })

    did_setup = true
end

function M.clear_pin()
    if M.active_pin then
        if vim.api.nvim_win_is_valid(M.active_pin.win_id) then
            vim.api.nvim_win_close(M.active_pin.win_id, true)
        end
        -- Cleanup the extmark so we don't leak memory
        if vim.api.nvim_buf_is_valid(M.active_pin.source_buf) then
            vim.api.nvim_buf_del_extmark(M.active_pin.source_buf, ns_id, M.active_pin.mark_id)
        end
        M.active_pin = nil
    end
end

function M.create_pin(lines, start_line)
    if #lines < 3 then return end

    M.clear_pin()

    local gutter_w, usable_width = get_layout_details()
    local source_buf = vim.api.nvim_get_current_buf()

    local mark_id = vim.api.nvim_buf_set_extmark(source_buf, ns_id, start_line, 0, {})
    local float_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value('filetype', vim.bo.filetype, { buf = float_buf })

    local display_height = math.min(#lines, M.config.max_height)
    local win_id = vim.api.nvim_open_win(float_buf, false, {
        relative = 'win',
        row = 0,
        col = gutter_w, -- Align exactly where text starts
        width = usable_width,
        style = 'minimal',
        height = display_height,
        border = M.config.border,
        title = " Pin ",
        title_pos = "right"
    })

    vim.api.nvim_set_option_value('winblend', M.config.winblend, { win = win_id })

    M.active_pin = {
        win_id = win_id,
        buf_id = float_buf,
        mark_id = mark_id,
        source_buf = source_buf,
        height = display_height
    }

    update_pin_position()
end

function M.pin_ts_node()
    local node = vim.treesitter.get_node()
    if not node then return end
    local srow, _, erow, _ = vim.treesitter.get_node_range(node)
    local lines = vim.api.nvim_buf_get_lines(0, srow, erow+1, false)
    M.create_pin(lines, srow - 1)
end

function M.pin_visual_selection()
    local spos = vim.fn.getpos("v")
    local epos = vim.fn.getpos(".")
    local sline = spos[2]
    local eline = epos[2]

    local from = math.min(sline, eline) -1
    local to = math.max(sline, eline)

    local lines = vim.api.nvim_buf_get_lines(0, from, to, false)
    M.create_pin(lines, from)
end

vim.schedule(function()
    if not did_setup then
        M.setup()
    end
end)

return M
