local M = { pins = {} }
local ns_id = vim.api.nvim_create_namespace("PinPlugin")
local did_setup = false

M.config = {
    winblend = 50,
    border = 'single',
    max_height = 15,
    keymaps = {
        pin_ts              = '<leader>ss',
        pin_visual          = '<leader>ss',
        clear_all_pins      = '<leader>sx',
        pin_pop             = '<leader>sp',
        pin_remove          = '<leader>sd'
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
    if #M.pins == 0 then return end

    local current_win = vim.api.nvim_get_current_win()
    local current_buf = vim.api.nvim_get_current_buf()
    local gutter_w, usable_width = get_layout_details()

    local top_offset = 0
    local bot_offset = 0

    for i, pin in ipairs(M.pins) do
        if vim.api.nvim_win_is_valid(pin.win_id) then
            if current_buf ~= pin.source_buf then
                vim.api.nvim_win_set_config(pin.win_id, { relative = "editor", row = 1000, col = 1000 })
            else
                local mark = vim.api.nvim_buf_get_extmark_by_id(pin.source_buf, ns_id, pin.mark_id, {})
                local mark_line = mark[1] +1

                local top_visible = vim.fn.line("w0")
                local bot_visible = vim.fn.line("w$") - 5

                local final_row = 0

                if mark_line < top_visible + top_offset then
                    final_row = top_offset
                    top_offset = top_offset+pin.height +2
                elseif mark_line + bot_offset > bot_visible then
                    bot_offset = bot_offset+pin.height +2
                    final_row = vim.api.nvim_win_get_height(current_win) - bot_offset
                else
                    final_row = mark_line - top_visible
                end

                vim.api.nvim_win_set_config(pin.win_id, {
                    relative = 'win',
                    win = current_win,
                    row = final_row,
                    col = gutter_w,
                    width = usable_width
                })
            end
        end
    end
end

function M.setup(user_config)
    M.config = vim.tbl_deep_extend("force", M.config, user_config or {})

    if M.config.keymaps then
        vim.keymap.set('n', M.config.keymaps.pin_ts, ':PinTS<CR>', {desc = "Pin TS Node"})
        vim.keymap.set('v', M.config.keymaps.pin_visual, ':PinVisual<CR>', {desc = "Pin Visual Selection"})
        vim.keymap.set('n', M.config.keymaps.pin_remove, ':PinRemove<CR>', {desc = "Pin Interactive Remove"})
        vim.keymap.set('n', M.config.keymaps.pin_pop, ':PinPop<CR>', {desc = "Pop the last Pin"})
        vim.keymap.set({'n','v'}, M.config.keymaps.clear_all_pins, ':PinClear<CR>', {desc = "Clear ALL Pins"})
    end

    local group = vim.api.nvim_create_augroup("PinScrollLogic", {clear = true})

    vim.api.nvim_create_autocmd({"WinScrolled", "CursorMoved"}, {
        group = group,
        callback = function() update_pin_position() end
    })

    did_setup = true
end

function M.pin_remove_interactive()
    if #M.pins == 0 then
        vim.notify("No pins to delete!")
        return
    end

    for i, pin in ipairs(M.pins) do
        if vim.api.nvim_win_is_valid(pin.win_id) then
            vim.api.nvim_win_set_config(pin.win_id, {
                title = " DELETE [" .. i .. "] ",
                title_pos = "center"
            })
        end
    end
    vim.cmd('redraw')

    vim.notify("󰐄 ")
    local index = vim.fn.getchar()
    M.pin_remove(vim.fn.nr2char(index))

    for i, pin in ipairs(M.pins) do
        if vim.api.nvim_win_is_valid(pin.win_id) then
            vim.api.nvim_win_set_config(pin.win_id, {
                title = " Pin " .. i .. " ",
                title_pos = "right"
            })
        end
    end
    vim.cmd('redraw')
    vim.api.nvim_echo({ { "", "" } }, false, {})
end

function M.pin_remove(index)
    if #M.pins == 0 then
        vim.notify("No pins to delete!")
        return
    end

    local idx = tonumber(index) or #M.pins
    local pin = M.pins[idx]

    if not pin then
        vim.notify("Pin " .. tostring(idx) .. " not found")
        return
    end

    if vim.api.nvim_win_is_valid(pin.win_id) then
        vim.api.nvim_win_close(pin.win_id, true)
    end
    if vim.api.nvim_buf_is_valid(pin.source_buf) then
        vim.api.nvim_buf_del_extmark(pin.source_buf, ns_id, pin.mark_id)
    end

    table.remove(M.pins, idx)
    update_pin_position()
end

function M.clear_pin()
    for _,pin in ipairs(M.pins) do
        if vim.api.nvim_win_is_valid(pin.win_id) then
            vim.api.nvim_win_close(pin.win_id, true)
        end

        if vim.api.nvim_buf_is_valid(pin.source_buf) then
            vim.api.nvim_buf_del_extmark(pin.source_buf, ns_id, pin.mark_id)
        end
    end
    M.pins = {}
end

function M.create_pin(lines, start_line)
    if #lines < 3 then return end

    local gutter_w, usable_width = get_layout_details()
    local source_buf = vim.api.nvim_get_current_buf()
    local ft = vim.bo.filetype

    local mark_id = vim.api.nvim_buf_set_extmark(source_buf, ns_id, start_line, 0, {})
    local float_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value('filetype', ft, { buf = float_buf })
    pcall(vim.treesitter.start, float_buf, ft)

    local display_height = math.min(#lines, M.config.max_height)

    local win_id = vim.api.nvim_open_win(float_buf, false, {
        relative = 'win',
        style = 'minimal',
        row = 0,
        col = gutter_w, -- Align exactly where text starts
        width = usable_width,
        height = display_height,
        border = M.config.border,
        title = " Pin " .. (#M.pins +1),
        title_pos = "right"
    })

    vim.api.nvim_set_option_value('winblend', M.config.winblend, { win = win_id })

    local new_pin = {
        win_id = win_id,
        buf_id = float_buf,
        mark_id = mark_id,
        source_buf = source_buf,
        height = display_height
    }
    table.insert(M.pins, new_pin)

    vim.api.nvim_buf_attach(source_buf, false, {
        on_lines = function(_, buf, _, _, _, _)
            vim.schedule(function() M.sync_specific_pin(new_pin) end)
        end
    })

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
