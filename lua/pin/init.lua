local M = {pins = {}}

M.indexof = function(obj)
    for i,v in ipairs(M.pins) do
        if v == obj then return i end
    end
    return nil
end

M.index_win_id = function(win_id)
    for i,v in ipairs(M.pins) do
        if v.win_id == win_id then return i end
    end
    return nil
end

local ns_id = vim.api.nvim_create_namespace("PinPlugin")
local main_window = vim.api.nvim_get_current_win()
local did_setup = false
local is_updating = false

M.config = {
    winblend = 50,
    border = 'single', -- none, single, double, rounded, solid, shadow
    max_height = 15,
    keymaps = {
        pin_ts              = '<leader>ss',
        pin_visual          = '<leader>ss',
        clear_all_pins      = '<leader>sx',
        pin_pop             = '<leader>sp',
        pin_remove          = '<leader>sd',
        focus_next          = '<leader>sn',
        focus_prev          = '<leader>sp'
    }
}

local function get_layout_details(win_id)
    local info = {
        vim = vim.fn.getwininfo(win_id or main_window)[1],
        nvim = vim.api.nvim_win_get_config(win_id or main_window)
    }
    local gutter_w = info.vim.textoff
    local win_w = info.nvim.width
    local available_w = win_w - gutter_w - 1
    return gutter_w, available_w
end

function M.update_pin_position()
    if #M.pins == 0 then return end

    local current_win = vim.api.nvim_get_current_win()
    local gutter_w, usable_width = get_layout_details()

    local view = vim.api.nvim_win_call(main_window, function()
        return vim.fn.winsaveview()
    end)

    local scroll_offset = (view.topline-1)

    local dbgln = {}
    for i, pin in ipairs(M.pins) do
        local offset = (i-1)*2

        if vim.api.nvim_win_is_valid(pin.win_id) then
            --local mark = vim.api.nvim_buf_get_extmark_by_id(pin.source_buf, ns_id, pin.mark_above, {})
            --local current_line = mark[1]

            --local screen_row = (current_line - (viewport.topline-1)) + 2*(#M.pins-1)

            local cursorpos, _ = vim.api.nvim_win_get_cursor(current_win)[1]
            table.insert(
                dbgln,
                string.format("at row: %d, pin top: %d, toprow: %d, topfill: %d",
                cursorpos, pin.spos, view.topline, view.topfill)
            )

            if pin.spos == view.topline then
                scroll_offset = scroll_offset+view.topfill
            end

            if pin.win_id ~= current_win then
                local is_active = cursorpos > pin.spos and cursorpos < pin.epos+2
                if is_active then
                    vim.api.nvim_set_current_win(pin.win_id)
                end
            end

            --vim.print("cursorpos: " .. cursorpos .. ", spos: " .. pin.spos .. ", epos: " .. pin.epos)

            current_win = vim.api.nvim_get_current_win()
            pin.focus = current_win == pin.win_id

            local border_hl = pin.focus and "DiagnosticInfo" or "FloatBorder"
            vim.api.nvim_set_option_value('winhighlight', 'FloatBorder:' .. border_hl, {win = pin.win_id})
            --vim.api.nvim_set_option_value('winhighlight', 'Normal:Pmenu,FloatBorder:Pmenu', { win = pin.win_id })
            vim.api.nvim_win_set_config(pin.win_id, {
                title = " Pin " .. i .. (current_win==pin.win_id and " 󰿆 " or " 󰌾 "),
                relative = 'win',
                win = main_window,
                --row = pin.mark_above - main_win_info.topline,
                row = (pin.spos+offset) - (scroll_offset),
                col = gutter_w,
                width = usable_width,
                height = pin.height
            })
        end
    end
    vim.notify_once(table.concat(dbgln, "\n"))
end

function M.setup(user_config)
    M.config = vim.tbl_deep_extend("force", M.config, user_config or {})

    if M.config.keymaps then
        vim.keymap.set('n', M.config.keymaps.pin_ts, ':PinTS<CR>', {desc = "Pin TS Node"})
        vim.keymap.set('v', M.config.keymaps.pin_visual, ':PinVisual<CR>', {desc = "Pin Visual Selection"})
        vim.keymap.set('n', M.config.keymaps.pin_remove, ':PinRemove<CR>', {desc = "Pin Interactive Remove"})
        vim.keymap.set('n', M.config.keymaps.pin_pop, ':PinPop<CR>', {desc = "Pop the last Pin"})
        vim.keymap.set({'n','v'}, M.config.keymaps.clear_all_pins, ':PinClear<CR>', {desc = "Clear ALL Pins"})
--        vim.keymap.set('n', M.config.keymaps.focus_next, ':PinPop<CR>', {desc = "Pop the last Pin"})
    end

    local group = vim.api.nvim_create_augroup("PinScrollLogic", {clear = false})

    vim.api.nvim_create_autocmd({"WinScrolled", "CursorMoved"}, {
        group = group,
        callback = function() M.update_pin_position() end
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
        vim.api.nvim_buf_del_extmark(pin.source_buf, ns_id, pin.mark_above)
        vim.api.nvim_buf_del_extmark(pin.source_buf, ns_id, pin.mark_below)
    end

    table.remove(M.pins, idx)
    M.update_pin_position()
end

function M.remove_pin_at(spos)
    for i, pin in ipairs(M.pins) do
        if pin.top_line == spos then
            M.pin_remove(i)
            return
        end
    end
end

function M.clear_pin()
    for _,pin in ipairs(M.pins) do
        if vim.api.nvim_win_is_valid(pin.win_id) then
            vim.api.nvim_win_close(pin.win_id, true)
        end

        if vim.api.nvim_buf_is_valid(pin.source_buf) then
            vim.api.nvim_buf_del_extmark(pin.source_buf, ns_id, pin.mark_above)
            vim.api.nvim_buf_del_extmark(pin.source_buf, ns_id, pin.mark_below)
        end
    end
    M.pins = {}
end

function M.create_pin(pin, lines)
    if vim.api.nvim_get_current_win() ~= main_window then
        M.pin_remove(M.index_win_id(vim.api.nvim_get_current_win()))
        return
    end

    local offset = #M.pins*2

    -- create and populate the buffer for the pin
    local gutter_w, usable_width = get_layout_details()
    local float_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
    local source_buf = vim.api.nvim_get_current_buf()

    local ft = vim.bo.filetype
    vim.api.nvim_set_option_value('modifiable', true, {buf = float_buf})
    vim.api.nvim_set_option_value('filetype', ft, { buf = float_buf })
    pcall(vim.treesitter.start, float_buf, ft)

    -- open the floating window with the buffer
    local win_id = vim.api.nvim_open_win(float_buf, false, {
        relative = 'win',
        style = 'minimal',
        row = pin.spos+offset,
        col = gutter_w, -- Align exactly where text starts
        width = usable_width,
        height = #lines,
        border = M.config.border,
        title = " Pin " .. (#M.pins +1),
        title_pos = "right"
    })
    vim.api.nvim_set_option_value('winblend', M.config.winblend, { win = win_id })


    -- populate and push pin to storage
    pin.win_id = win_id
    pin.buf_id = float_buf
    pin.source_buf = source_buf
    pin.height = #lines
    table.insert(M.pins, pin)

    vim.keymap.set('n', 'j', function ()
        local row,col = unpack(vim.api.nvim_win_get_cursor(pin.win_id))
        if row == pin.height then
            vim.api.nvim_set_current_win(main_window)
            vim.api.nvim_win_set_cursor(main_window, {pin.epos+2, col})
        else
            vim.api.nvim_feedkeys('j', 'n', false)
        end
    end, { buffer = float_buf, silent = true })

    vim.keymap.set('n', 'k', function ()
        local row,col = unpack(vim.api.nvim_win_get_cursor(0))
        if row == 1 then
            vim.api.nvim_set_current_win(main_window)
            vim.api.nvim_win_set_cursor(main_window, {pin.spos, col})
        else
            vim.api.nvim_feedkeys('k', 'n', false)
        end
    end, { buffer = float_buf, silent = true })

    -- setup handling for changes to keep main buffer synced with the floating window
    vim.api.nvim_buf_attach(float_buf, false, {
        on_lines = function(_, _, _, firstline, lastline, new_lastline)
            local new_text = vim.api.nvim_buf_get_lines(float_buf, firstline, new_lastline, false)
            local mark = vim.api.nvim_buf_get_extmark_by_id(source_buf, ns_id, mark_start_id, {})
            local source_start = mark[1] + firstline
            local source_end = mark[1] + lastline

            vim.schedule(function()
                vim.api.nvim_buf_set_lines(source_buf, source_start+1, source_end+1, false, new_text)
            end)
        end
    })

    M.update_pin_position()
end

function M.pin_ts_node()
    local node = vim.treesitter.get_node()
    if not node then return end

    local offset = #M.pins*2
    local spos, _, epos , _ = vim.treesitter.get_node_range(node)

    local pin_id_above = vim.api.nvim_buf_set_extmark(vim.api.nvim_get_current_buf(), ns_id, spos, 0, {
        virt_lines = { { { " ", "NonText" } } },
        virt_lines_above = true,
    })

    local pin_id_below = vim.api.nvim_buf_set_extmark(vim.api.nvim_get_current_buf(), ns_id, epos, 0, {
        virt_lines = { { { " ", "NonText" } } },
        virt_lines_above = false,
    })

    local lines = vim.api.nvim_buf_get_lines(0, spos, epos+1, false)

    local new_pin = {
        win_id = nil,
        buf_id = nil,
        source_buf = nil,
        spos = spos,
        epos = epos,
        mark_above = pin_id_above,
        mark_below = pin_id_below,
        top_line = 0,
        height = #lines
    }

    M.create_pin(new_pin, lines)
end

function M.pin_visual_selection()
    local spos = vim.fn.getpos("'<")[2]-1
    local epos = vim.fn.getpos("'>")[2]-1

    --vim.print("spos: " .. spos .. ", epos: " .. epos)
    local from = math.min(spos, epos)
    local to = math.max(spos, epos)

    local pin_id_above = vim.api.nvim_buf_set_extmark(vim.api.nvim_get_current_buf(), ns_id, spos, 0, {
        virt_lines = { { { " ", "NonText" } } },
        virt_lines_above = true,
    })
    local pin_id_below = vim.api.nvim_buf_set_extmark(vim.api.nvim_get_current_buf(), ns_id, epos, 0, {
        virt_lines = { { { " ", "NonText" } } },
        virt_lines_above = false,
    })
    local lines = vim.api.nvim_buf_get_lines(0, from, to, false)

    local new_pin = {
        win_id = nil,
        buf_id = nil,
        source_buf = nil,
        spos = spos,
        epos = epos,
        mark_above = pin_id_above,
        mark_below = pin_id_below,
        top_line = 0,
        height = epos-spos+1
    }
    M.create_pin(new_pin, lines)
end

vim.schedule(function()
    if not did_setup then
        M.setup()
    end
end)

return M
