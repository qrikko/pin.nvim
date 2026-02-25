local M = {pins = {}, topfill = 0}

local ns_id = vim.api.nvim_create_namespace("PinPlugin")
local main_window = vim.api.nvim_get_current_win()
local backdrop_win = nil
local did_setup = false

local function clamp(value, min, max)
  return math.max(min, math.min(max, value))
end

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

local function create_backdrop()
    local buf = vim.api.nvim_create_buf(false, true)

    backdrop_win = vim.api.nvim_open_win(buf, false, {
        relative = 'editor',
        width = vim.o.columns,
        height = vim.o.lines - vim.o.cmdheight,
        row = 0,
        col = 0,
        style = 'minimal',
        focusable = false,
        zindex = 1
    })
    vim.api.nvim_set_option_value("winhighlight", "Normal:pinvim_backdrop", {win = backdrop_win })
    vim.api.nvim_set_option_value("winblend", M.config.backdrop.alpha, { win = backdrop_win })
end

local function close_backdrop()
    if backdrop_win and vim.api.nvim_win_is_valid(backdrop_win) then
        vim.api.nvim_win_close(backdrop_win, true)
        backdrop_win = nil
    end
end

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

M.config = {
    winblend = 50,
    border = 'none', -- none, single, double, rounded, solid, shadow
    max_height = 15,
    keymaps = {
        pin_ts              = '<leader>ss',
        pin_visual          = '<leader>ss',
        clear_all_pins      = '<leader>sx',
        pin_pop             = '<leader>sp',
        pin_remove          = '<leader>sd',
        focus_next          = '<leader>sn',
        focus_prev          = '<leader>sp',
        focus_pin           = '<leader>sg'
    },
    symbol = {
        locked = {
            bg = "#1a1024",
            fg = "#ff995f",
            sym = "󰌾 ",
            bold = true,
            winhighlight = "Normal:pinvim_window_locked,FloatBorder:pinvim_window_locked",

        },
        unlocked = {
            bg = "#11071b",
            fg = "#ff995f",
            sym = "󰿆 ",
            bold = true,
            winhighlight = "Normal:pinvim_window_unlocked,FloatBorder:pinvim_window_unlocked"
        },
        pinned = {
            bg = "#2e2439",
            fg = "#ff995f",
            sym = " ",
            bold = true,
            winhighlight = "Normal:pinvim_window_pinned,FloatBorder:pinvim_window_pinned"
        },
    },
    backdrop = {
        bg = "#000000",
        alpha = 40
    },
}

function M.setup(user_config)
    M.config = vim.tbl_deep_extend("force", M.config, user_config or {})

    M.scrolloff = vim.o.scrolloff

    local s = M.config.symbol
    vim.api.nvim_set_hl(0, "pinvim_symbol_locked",      { bg=s.locked.bg, fg=s.locked.fg, bold=s.locked.bold })
    vim.api.nvim_set_hl(0, "pinvim_symbol_unlocked",    { bg=s.unlocked.bg, fg=s.unlocked.fg, bold=s.unlocked.bold })
    vim.api.nvim_set_hl(0, "pinvim_symbol_pinned",      { bg=s.pinned.bg, fg=s.pinned.fg, bold=s.pinned.bold })

    vim.api.nvim_set_hl(0, "pinvim_window_locked",     { bg=s.locked.bg })
    vim.api.nvim_set_hl(0, "pinvim_window_unlocked",   { bg=s.unlocked.bg })
    vim.api.nvim_set_hl(0, "pinvim_window_pinned",     { bg=s.pinned.bg, fg=s.pinned.fg })

    vim.api.nvim_set_hl(0, "pinvim_backdrop",    { bg=M.config.backdrop.bg, default = true })

    if M.config.keymaps then
        vim.keymap.set('n', M.config.keymaps.pin_ts, ':PinTS<CR>', {desc = "Pin TS Node"})
        vim.keymap.set('v', M.config.keymaps.pin_visual, ':PinVisual<CR>', {desc = "Pin Visual Selection"})
        vim.keymap.set('n', M.config.keymaps.pin_remove, ':PinRemove<CR>', {desc = "Pin Interactive Remove"})
        vim.keymap.set('n', M.config.keymaps.pin_pop, ':PinPop<CR>', {desc = "Pop the last Pin"})
        vim.keymap.set('n', M.config.keymaps.focus_next, ':PinFocusNext<CR>', {desc = "Jump to next pin"})
        vim.keymap.set('n', M.config.keymaps.focus_prev, ':PinFocusPrev<CR>', {desc = "Jump to next pin"})
        vim.keymap.set('n', M.config.keymaps.focus_pin, ':PinFocusVisual<CR>', {desc = "Select pin interactively and jump to it"})

        vim.keymap.set({'n','v'}, M.config.keymaps.clear_all_pins, ':PinClear<CR>', {desc = "Clear ALL Pins"})
    end

    local group = vim.api.nvim_create_augroup("PinScrollLogic", {clear = false})

    vim.api.nvim_create_autocmd({"WinScrolled", "CursorMoved"}, {
        group = group,
        callback = function() M.update_pin_position() end
    })

    did_setup = true
end

function M.update_pin_position()
    if #M.pins == 0 then return end

    local current_win = vim.api.nvim_get_current_win()
    local gutter_w, usable_width = get_layout_details()

    local view = vim.api.nvim_win_call(main_window, function()
        return vim.fn.winsaveview()
    end)

    local scroll_top = (view.topline-1)
    local cursorpos = vim.api.nvim_win_get_cursor(current_win)[1]
    local main_buffer = vim.api.nvim_win_get_buf(main_window)

    local top     = vim.fn.line('w0', main_window) -1
    local bottom    = vim.fn.line('w$', main_window) - top
    local buf_bottom = vim.fn.line('w$', main_window)

    local top_stack = 0
    local bottom_stack = 0

    for i, pin in ipairs(M.pins) do
        if vim.api.nvim_win_is_valid(pin.win_id) then
            if pin.win_id ~= current_win then
                local is_active = cursorpos > pin.spos and cursorpos < pin.epos+2
                if is_active then
                    vim.api.nvim_set_current_win(pin.win_id)
                    local r,c = unpack(vim.api.nvim_win_get_cursor(main_window))
                    vim.api.nvim_win_set_cursor(pin.win_id, {r-pin.spos, c})
                    M.focused_id = i
                end
            end
            current_win = vim.api.nvim_get_current_win()

            local pin_top = math.min(math.max(pin.spos-top, top_stack), bottom-pin.height)
            local pin_bottom = pin_top+pin.height

            local state = nil
            if pin_top <= top_stack or pin_bottom >= bottom then
                state = M.config.symbol.pinned
                state.sym_hl = "pinvim_symbol_pinned"
                state.win_hl = "pinvim_window_pinned"
            elseif current_win==pin.win_id then
                state = M.config.symbol.unlocked
                state.sym_hl = "pinvim_symbol_unlocked"
                state.win_hl = "pinvim_window_unlocked"
            else
                state = M.config.symbol.locked
                state.sym_hl = "pinvim_symbol_locked"
                state.win_hl = "pinvim_window_locked"
            end

            vim.api.nvim_win_set_config(pin.win_id, {
                relative = 'win',
                win = main_window,
                row = pin_top,
                col = gutter_w,
                width = usable_width,
                height = pin.height,
                focusable = false,
            })

            local sign_top_row = math.max(pin.spos, scroll_top+top_stack)
            sign_top_row = math.min(sign_top_row, buf_bottom-pin.height-bottom_stack)

            vim.api.nvim_buf_set_extmark(main_buffer, ns_id, sign_top_row, 0, {
                id = pin.mark_pin_id,
                sign_text = state.sym,
                sign_hl_group = state.sym_hl,
                number_hl_group = state.sym_hl,
                priority = 100
            })

            vim.api.nvim_set_option_value("winhighlight", state.winhighlight, {win=pin.win_id})

            if pin_top <= top_stack then
                top_stack = top_stack + pin.height
            end
            if pin_bottom >= bottom then
                bottom = bottom - pin.height
                bottom_stack = bottom_stack + pin.height
            end
        end
    end

    --local scrolloff = math.max(M.scrolloff, math.max(top_stack+2, bottom_stack+2))
    local scrolloff = M.scrolloff + math.max(top_stack+2, bottom_stack+2)
    vim.api.nvim_set_option_value("scrolloff", scrolloff, {win=main_window})
end

function M.select_interactive(prompt)
    if #M.pins == 0 then
        vim.notify("No selectable pins!")
        return
    end

    create_backdrop()

    for i, pin in ipairs(M.pins) do
        if vim.api.nvim_win_is_valid(pin.win_id) then
            vim.api.nvim_win_set_config(pin.win_id, {
                title = " #ID [" .. i .. "] ",
                title_pos = "left",
                border = "rounded"
            })
        end
    end
    vim.cmd('redraw')

    vim.notify(prompt)
    local result = vim.fn.getchar() - 48

    for i, pin in ipairs(M.pins) do
        if vim.api.nvim_win_is_valid(pin.win_id) then
            vim.api.nvim_win_set_config(pin.win_id, {
                title = " Pin " .. i .. " ",
                title_pos = "right",
                border = "none"
            })
        end
    end
    close_backdrop()
    vim.cmd('redraw')
    vim.api.nvim_echo({ { "", "" } }, false, {})

    return result
end

function M.pin_remove_interactive()
    local index = M.select_interactive("󰐄 Remove pin by id:")

    if index ~= nil then
        M.pin_remove(index)
    end
end

function M.pin_remove(index)
    if #M.pins == 0 then
        vim.notify("No pins to delete!")
        return
    end

    --local idx = tonumber(index) or #M.pins
    local pin = M.pins[index]

    if not pin then
        vim.notify("Pin " .. tostring(index) .. " not found")
        return
    end

    if vim.api.nvim_win_is_valid(pin.win_id) then
        vim.api.nvim_win_close(pin.win_id, true)
    end

    local main_buffer = vim.api.nvim_win_get_buf(main_window)
    vim.api.nvim_buf_del_extmark(main_buffer, ns_id, pin.mark_pin_id)

    table.remove(M.pins, index)
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
    for i = #M.pins, 1, -1 do
        M.pin_remove(i)
    end
end

function M.pin_focus_interactive()
    local index = M.select_interactive("󱔔 Jump to pin by id:")
    if index then
        M.pin_focus(index)
    end
end

function M.pin_focus(id)
    local pin = M.pins[id]
    vim.api.nvim_win_set_cursor(main_window, {pin.spos+1, 0})
    vim.api.nvim_set_current_win(pin.win_id)
    vim.api.nvim_win_set_cursor(pin.win_id, {1, 0})
    M.focused_id = id
end

function M.pin_focus_next()
    M.focused_id = M.focused_id + 1
    local id = (M.focused_id > #M.pins) and 1 or M.focused_id
    M.pin_focus(id)
end

function M.pin_focus_prev()
    M.focused_id = M.focused_id - 1
    local id = (M.focused_id < 1) and #M.pins or M.focused_id
    M.pin_focus(id)
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

    pin.mark_pin_id =   vim.api.nvim_buf_set_extmark(source_buf, ns_id, pin.spos, 0, {})

    -- open the floating window with the buffer
    local win_id = vim.api.nvim_open_win(float_buf, false, {
        relative = 'win',
        win = main_window,
        style = 'minimal',
        bufpos = {pin.spos, 0},
        width = usable_width,
        height = #lines,
        border = 'none',-- M.config.border,
        title = " Pin " .. (#M.pins +1),
        title_pos = "right",
        focusable = false,
    })
    local is_dark = vim.o.background == "dark"
    vim.api.nvim_set_option_value("winhighlight",
        "Normal:pinvim_window_unlocked," ..
        "FloatBorder:pinvim_window_locked",
        {win=win_id}
    )

    -- populate and push pin to storage
    pin.win_id = win_id
    pin.buf_id = float_buf
    pin.source_buf = source_buf
    pin.height = #lines
    table.insert(M.pins, pin)
    M.pins.focused_id = #M.pins

    vim.keymap.set('n', 'j', function ()
        local row,col = unpack(vim.api.nvim_win_get_cursor(pin.win_id))
        if row == pin.height then
            vim.api.nvim_set_current_win(main_window)
            vim.api.nvim_win_set_cursor(main_window, {pin.spos+pin.height+1, col})
        else
            vim.api.nvim_feedkeys('j', 'n', false)
            vim.cmd("normal! zz")
        --    local mrow,mcol = unpack(vim.api.nvim_win_get_cursor(main_window))
        --    vim.api.nvim_win_set_cursor(main_window, {mrow+1, mcol})
        end
    end, { buffer = float_buf, silent = true })

    vim.keymap.set('n', 'k', function ()
        local row,col = unpack(vim.api.nvim_win_get_cursor(0))
        if row == 1 then
            vim.api.nvim_set_current_win(main_window)
            vim.api.nvim_win_set_cursor(main_window, {pin.spos, col})
        else
            vim.api.nvim_feedkeys('k', 'n', false)
            vim.cmd("normal! zz")
            --[[
            local mrow,mcol = unpack(vim.api.nvim_win_get_cursor(main_window))
            vim.api.nvim_win_set_cursor(main_window, {mrow-1, mcol})
            ]]
        end
    end, { buffer = float_buf, silent = true })

    vim.keymap.set('n', 'G', function()
        vim.api.nvim_set_current_win(main_window)
        vim.cmd("normal! G")
    end, { buffer = float_buf, silent = true })

    vim.keymap.set('n', 'gg', function()
        vim.api.nvim_set_current_win(main_window)
        vim.cmd("normal! gg")
    end, { buffer = float_buf, silent = true })

    vim.api.nvim_create_autocmd('CmdLineEnter', {
        callback = function()
            local cmd = vim.fn.getcmdline()
            vim.fn.setcmdline('')
            vim.defer_fn(function()
                vim.api.nvim_set_current_win(main_window)
                vim.cmd(cmd)
            end, 0)
        end,
        desc = "Redirect cmdline to main window"
    })

    -- setup handling for changes to keep main buffer synced with the floating window
    vim.api.nvim_buf_attach(float_buf, false, {
        on_lines = function(_, _, _, firstline, lastline, new_lastline)
            local new_text = vim.api.nvim_buf_get_lines(float_buf, firstline, new_lastline, false)
            --local mark = vim.api.nvim_buf_get_extmark_by_id(source_buf, ns_id, mark_start_id, {})
            local pin_pos = pin.spos + vim.fn.line('.') -1

            --local source_start = pin.spos + firstline
            --local source_end = pin.spos+pin.height + lastline

            vim.schedule(function()
                vim.api.nvim_buf_set_lines(source_buf, pin_pos, pin_pos+1, false, new_text)
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

    local lines = vim.api.nvim_buf_get_lines(0, spos, epos+1, false)
    local new_pin = {
        win_id = nil,
        buf_id = nil,
        source_buf = nil,
        spos = spos,
        epos = epos,
        top_line = 0,
        height = #lines
    }

    M.create_pin(new_pin, lines)
end

function M.pin_visual_selection()
    local spos = vim.fn.getpos("'<")[2]-1
    local epos = vim.fn.getpos("'>")[2]-1

    local from = math.min(spos, epos)
    local to = math.max(spos, epos)

    local lines = vim.api.nvim_buf_get_lines(0, from, to, false)

    local new_pin = {
        win_id = nil,
        buf_id = nil,
        source_buf = nil,
        spos = spos,
        epos = epos,
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
