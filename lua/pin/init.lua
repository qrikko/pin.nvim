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
        focus_prev          = '<leader>sp'
    },
    lock_symbol = {
        norm = {
            bg = "#3c3246",
            fg = "#ff995f",
            bold = true
        },
        hl = {
            bg = "#1e283c",
            fg = "#ff995f",
            bold = true
        },
    },
    pin_window = {
        norm = { bg = "#3c3246" },
        hl = { bg = "#1e283c" }
    },
    backdrop = {
        bg = "#000000",
        alpha = 40
    },
}

function M.setup(user_config)
    M.config = vim.tbl_deep_extend("force", M.config, user_config or {})

    local s = M.config.lock_symbol
    vim.api.nvim_set_hl(0, "pinvim_symbol_hl",   { bg=s.hl.bg,   fg=s.hl.fg, bold=true })
    vim.api.nvim_set_hl(0, "pinvim_symbol_norm", { bg=s.norm.bg, fg=s.norm.fg, bold=true })
    vim.api.nvim_set_hl(0, "pinvim_win_hl",      { bg=M.config.pin_window.hl.bg })
    vim.api.nvim_set_hl(0, "pinvim_win_norm",    { bg=M.config.pin_window.norm.bg })
    vim.api.nvim_set_hl(0, "pinvim_backdrop",    { bg=M.config.backdrop.bg, default = true })

    if M.config.keymaps then
        vim.keymap.set('n', M.config.keymaps.pin_ts, ':PinTS<CR>', {desc = "Pin TS Node"})
        vim.keymap.set('v', M.config.keymaps.pin_visual, ':PinVisual<CR>', {desc = "Pin Visual Selection"})
        vim.keymap.set('n', M.config.keymaps.pin_remove, ':PinRemove<CR>', {desc = "Pin Interactive Remove"})
        vim.keymap.set('n', M.config.keymaps.pin_pop, ':PinPop<CR>', {desc = "Pop the last Pin"})
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
    local scroll_bottom = vim.api.nvim_win_get_height(main_window)
    local cursorpos = vim.api.nvim_win_get_cursor(current_win)[1]
    local main_buffer = vim.api.nvim_win_get_buf(main_window)

    local top     = vim.fn.line('w0', main_window) -1
    local current   = vim.fn.line('.', main_window)
    local bottom    = vim.fn.line('w$', main_window) - top

    local top_stack = 0
    local bottom_stack = 0

    --[[
    for _, pin in ipairs(M.pins) do
        local pin_top = pin.spos - scroll_top
        pin._pinned = 0
        if pin_top <= top_stack then
            pin._pinned = 1
            top_stack = top_stack + pin.height
        end
    end
    top_stack = 0
    ]]

    for _, pin in ipairs(M.pins) do
        if vim.api.nvim_win_is_valid(pin.win_id) then
            if pin.win_id ~= current_win then
                local is_active = cursorpos > pin.spos and cursorpos < pin.epos+2
                if is_active then
                    vim.api.nvim_set_current_win(pin.win_id)
                    local r,c = unpack(vim.api.nvim_win_get_cursor(main_window))
                    vim.api.nvim_win_set_cursor(pin.win_id, {r-pin.spos, c})
                end
            end
            current_win = vim.api.nvim_get_current_win()

            local pin_hl = current_win==pin.win_id and "pinvim_win_hl" or "pinvim_win_norm"
            local lock_hl = current_win==pin.win_id and "pinvim_symbol_hl" or "pinvim_symbol_norm"

            vim.print("top: " .. top_stack .. ", bottom: " .. bottom_stack)
            local pin_top = math.min(math.max(pin.spos-top, top_stack), bottom-bottom_stack-pin.height)
            local pin_bottom = pin_top+pin.height
            --local pin_top = pin.spos-top
            --vim.print("top: " .. top ..  ", pin top: " .. pin_top .. ", pin bottom: " .. pin_bottom .. ", bottom: " .. bottom)
            --local pin_top   = math.min(pin.spos+scroll_top+pin.height, scroll_bottom)
            --pin_top         = math.max(pin.spos - scroll_top, top_stack)
--            vim.print("pin top: " .. pin_top .. ", top: " .. view.topline .. ", bottom: " .. scroll_bottom)

            vim.api.nvim_win_set_config(pin.win_id, {
                relative = 'win',
                win = main_window,
                row = pin_top,
                col = gutter_w,
                width = usable_width,
                height = pin.height
            })


            local sign_top_row = math.max(pin.spos, scroll_top)
            --local sign_bottom_row = math.min(sign_top_row+pin.height-1, scroll_bottom)

            vim.api.nvim_buf_set_extmark(main_buffer, ns_id, sign_top_row, 0, {
                id = pin.mark_pin_id,
                sign_text = (pin_top <= top_stack or pin_bottom >= bottom) and " " or (current_win==pin.win_id and "󰿆 " or "󰌾 "),
                sign_hl_group = lock_hl,
                number_hl_group = lock_hl,
                priority = 100
            })

            vim.api.nvim_set_option_value("winhighlight",
                "Normal:" .. pin_hl .. "," ..
                "FloatBorder:" .. pin_hl,
                {win=pin.win_id}
            )

            if pin_top <= top_stack then
                top_stack = top_stack + pin.height
            end
            if pin_bottom >= bottom then
                bottom = bottom - pin.height
            end
        end
    end
end

function M.pin_remove_interactive()
    if #M.pins == 0 then
        vim.notify("No pins to delete!")
        return
    end

    create_backdrop()

    for i, pin in ipairs(M.pins) do
        if vim.api.nvim_win_is_valid(pin.win_id) then
            vim.api.nvim_win_set_config(pin.win_id, {
                title = " DELETE [" .. i .. "] ",
                title_pos = "left",
                border = "rounded"
            })
        end
    end
    vim.cmd('redraw')

    vim.notify("󰐄 Remove pin by id:")
    local index = vim.fn.getchar()
    --M.pin_remove(index)
    M.pin_remove(vim.fn.nr2char(index))

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

    local main_buffer = vim.api.nvim_win_get_buf(main_window)
    vim.api.nvim_buf_del_extmark(main_buffer, ns_id, pin.mark_pin_id)
    --vim.api.nvim_buf_del_extmark(main_buffer, ns_id, pin.mark_block_id)

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
            --vim.api.nvim_buf_del_extmark(pin.source_buf, ns_id, pin.mark_above)
            --vim.api.nvim_buf_del_extmark(pin.source_buf, ns_id, pin.mark_below)
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

    pin.mark_pin_id =   vim.api.nvim_buf_set_extmark(source_buf, ns_id, pin.spos, 0, {})

    -- open the floating window with the buffer
    local win_id = vim.api.nvim_open_win(float_buf, false, {
        relative = 'win',
        win = main_window,
        style = 'minimal',
        bufpos = {pin.spos, 0},
        --row = pin.spos, -- +offset,
        --col = 0, --gutter_w, -- Align exactly where text starts
        width = usable_width,
        height = #lines,
        border = 'none',-- M.config.border,
        title = " Pin " .. (#M.pins +1),
        title_pos = "right"
    })
    local is_dark = vim.o.background == "dark"
    vim.api.nvim_set_option_value("winhighlight",
        "Normal:pinvim_win_norm," ..
        "FloatBorder:pinvim_win_hl",
        {win=win_id}
    )

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

    -- setup handling for changes to keep main buffer synced with the floating window
    --[[
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
    ]]

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
