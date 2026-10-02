local M = {pins = {}, topfill = 0}

local ns_id = vim.api.nvim_create_namespace("PinPlugin")
local main_window = vim.api.nvim_get_current_win()
local backdrop_win = nil
local did_setup = false

-- every pin is anchored to this window, so it has to survive the user closing
-- or splitting it. fall back to wherever we are rather than erroring out.
local function anchor_window()
    if not vim.api.nvim_win_is_valid(main_window) then
        main_window = vim.api.nvim_get_current_win()
    end
    return main_window
end

local function get_layout_details(win_id)
    local win = win_id or anchor_window()
    local info = {
        vim = vim.fn.getwininfo(win)[1],
        nvim = vim.api.nvim_win_get_config(win)
    }
    local gutter_w = info.vim.textoff
    local win_w = info.nvim.width
    local available_w = win_w - gutter_w - 1
    return gutter_w, available_w
end

-- screen row of a 1 indexed buffer line in the main window, folds included.
-- lines which are not displayed are pinned to the edge they scrolled out of.
local function screen_row(lnum, top_lnum, bottom)
    local row = vim.fn.screenpos(anchor_window(), lnum, 1).row
    if row > 0 then return row-1 end
    if lnum < top_lnum then return -1 end
    return bottom
end

-- buffer line to hang a sign on, kept inside the lines the main window shows.
local function clamp_lnum(lnum, from, to)
    return math.max(from, math.min(lnum, math.max(from, to)))
end

-- a sign inside a closed fold is never drawn, so move it onto the fold line
local function sign_lnum(lnum, from, to)
    lnum = clamp_lnum(lnum, from, to)
    local fold = vim.fn.foldclosed(lnum)
    if fold > 0 then lnum = clamp_lnum(fold, from, to) end
    return lnum
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

-- index of the pin covering a 1 indexed line of a pin's source buffer, or nil
M.pin_at_lnum = function(bufnr, lnum)
    for i = #M.pins, 1, -1 do
        local pin = M.pins[i]
        if pin.source_buf == bufnr and lnum >= pin.spos+1 and lnum <= pin.epos+1 then
            return i
        end
    end
    return nil
end

-- where the user is acting, always expressed against a pin's source buffer.
-- a pin is a portal into the main buffer, so a cursor sitting inside a pin
-- maps back onto the main buffer lines that pin covers. without this every
-- command run from inside a pin would act on the pin's scratch buffer.
M.context = function()
    local win = vim.api.nvim_get_current_win()
    local idx = M.index_win_id(win)

    if not idx then
        local anchor = anchor_window()
        return {
            win = anchor,
            buf = vim.api.nvim_win_get_buf(anchor),
            lnum = vim.api.nvim_win_get_cursor(win)[1],
            pin = nil
        }
    end

    local pin = M.pins[idx]
    return {
        win = pin.win_id,
        buf = pin.source_buf,
        lnum = pin.spos + vim.api.nvim_win_get_cursor(win)[1],
        pin = pin
    }
end

M.config = {
    winblend = 50,
    border = 'none', -- none, single, double, rounded, solid, shadow
    max_height = 15,
    -- pull the cursor into the new pin right away. leaving it in the main
    -- window is friendlier, the pin is still one cursor move away
    focus_on_create = false,
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
            bg = "#11071b",
            fg = "#ff995f",
            sym = "󰌾 ",
            bold = true,
            winhighlight = "Normal:pinvim_window_locked,FloatBorder:pinvim_window_locked",

        },
        unlocked = {
            bg = "#0a0014",
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
        vim.keymap.set('n', M.config.keymaps.pin_ts, ':PinToggle<CR>', {desc = "Pin the block at cursor, or unpin it"})
        vim.keymap.set('x', M.config.keymaps.pin_visual, '<Esc>:PinVisual<CR>', {desc = "Pin Visual Selection"})
        vim.keymap.set('n', M.config.keymaps.pin_remove, ':PinRemove<CR>', {desc = "Pin Interactive Remove"})
        vim.keymap.set('n', M.config.keymaps.pin_pop, ':PinPop<CR>', {desc = "Pop the last Pin"})
        vim.keymap.set('n', M.config.keymaps.focus_next, ':PinFocusNext<CR>', {desc = "Jump to next pin"})
        vim.keymap.set('n', M.config.keymaps.focus_prev, ':PinFocusPrev<CR>', {desc = "Jump to next pin"})
        vim.keymap.set('n', M.config.keymaps.focus_pin, ':PinFocusVisual<CR>', {desc = "Select pin interactively and jump to it"})

        vim.keymap.set({'n','v'}, M.config.keymaps.clear_all_pins, ':PinClear<CR>', {desc = "Clear ALL Pins"})
    end

    local group = vim.api.nvim_create_augroup("PinScrollLogic", {clear = false})

    -- SafeState catches everything which relayouts the main window without
    -- scrolling it, zc/zo/zO for instance. only a cursor move may pull the
    -- focus into a pin, so that is the only event asking for focus.
    vim.api.nvim_create_autocmd({"WinScrolled", "CursorMoved", "WinResized", "VimResized", "SafeState", "BufEnter", "ModeChanged", "WinEnter"}, {
        group = group,
        callback = function(args)
            M.update_pin_position(args.event == "CursorMoved")
        end
    })

    -- a pin is only a view onto the main buffer, so a command typed from inside
    -- one has to act on the main window. CmdLineEnter fires on the first :, so
    -- the switch has to be deferred, doing it inline throws the command line
    -- away. this used to run for every command line in the editor, once per pin
    -- ever made, so it now only steps in when a pin actually has focus
    vim.api.nvim_create_autocmd('CmdLineEnter', {
        group = vim.api.nvim_create_augroup("PinCmdline", {clear = true}),
        callback = function()
            if not M.index_win_id(vim.api.nvim_get_current_win()) then return end
            vim.defer_fn(function()
                vim.api.nvim_set_current_win(anchor_window())
            end, 0)
        end,
        desc = "Redirect cmdline to main window"
    })

    did_setup = true
end

function M.update_pin_position(focus)
    local anchor = anchor_window()

    -- the last pin is gone, hand the main window its scrolloff back
    if #M.pins == 0 then
        if vim.api.nvim_get_option_value("scrolloff", {win=anchor}) ~= M.scrolloff then
            vim.api.nvim_set_option_value("scrolloff", M.scrolloff, {win=anchor})
        end
        return
    end

    local current_win = vim.api.nvim_get_current_win()
    local gutter_w, usable_width = get_layout_details(anchor)

    local cursorpos = vim.api.nvim_win_get_cursor(current_win)[1]
    local main_buffer = vim.api.nvim_win_get_buf(anchor)

    -- buffer lines the main window is currently showing, 1 indexed
    local top_lnum  = vim.fn.line('w0', anchor)
    local bot_lnum  = vim.fn.line('w$', anchor)
    -- screen rows the pins have to be laid out in. a closed fold eats as many
    -- rows as it has lines, so the window height is the only reliable bottom
    local win_h = vim.api.nvim_win_get_height(anchor)
    local bottom = win_h

    -- a pin taller than the window can never be fully shown, cap it so the
    -- stacking below it still adds up
    local max_h = math.max(1, math.min(M.config.max_height or win_h, win_h-2))

    local top_stack = 0
    local bottom_stack = 0

    for i, pin in ipairs(M.pins) do
        if vim.api.nvim_win_is_valid(pin.win_id) then
            -- height in screen lines: can change if folds exist inside pin window
            local win_h_pin = vim.api.nvim_win_get_height(pin.win_id)
            local text_h = vim.api.nvim_win_text_height(pin.win_id, {})
            local vis_h = math.min((text_h and text_h.all) or pin.height, max_h)

            if focus and pin.win_id ~= current_win then
                local is_active = cursorpos > pin.spos and cursorpos < pin.spos+2
                if is_active then
                    vim.api.nvim_set_current_win(pin.win_id)
                    local r,c = unpack(vim.api.nvim_win_get_cursor(anchor))
                    vim.api.nvim_win_set_cursor(pin.win_id, {r-pin.spos, c})
                    M.focused_id = i
                end
            end
            current_win = vim.api.nvim_get_current_win()

            local pin_top = math.min(math.max(screen_row(pin.spos+1, top_lnum, bottom), top_stack),
                                     math.max(bottom-vis_h, 0))
            local pin_bottom = pin_top+vis_h

            local state, sym_hl = nil, nil
            if pin_top <= top_stack or pin_bottom >= bottom then
                state, sym_hl = M.config.symbol.pinned, "pinvim_symbol_pinned"
            elseif current_win==pin.win_id then
                state, sym_hl = M.config.symbol.unlocked, "pinvim_symbol_unlocked"
            else
                state, sym_hl = M.config.symbol.locked, "pinvim_symbol_locked"
            end

            local placed = pin.placed
            -- always update height to match text height when folds change
            if vim.api.nvim_win_get_height(pin.win_id) ~= vis_h then
                vim.api.nvim_win_set_height(pin.win_id, vis_h)
            end
            vim.api.nvim_win_set_config(pin.win_id, {
                relative = 'win',
                win = anchor,
                row = pin_top,
                col = gutter_w,
                width = usable_width,
                height = vis_h,
                focusable = false,
            })
            vim.api.nvim_set_option_value("winhighlight", state.winhighlight, {win=pin.win_id})
            pin.placed = {
                top = pin_top,
                width = usable_width,
                height = vis_h,
                win_hl = state.winhighlight
            }

            -- 1 indexed, the +1 keeps the sign out of the rows the pin covers
            local sign_row = sign_lnum(pin.spos+1, top_lnum+top_stack, bot_lnum-vis_h-bottom_stack+1)-1
            if not placed or placed.sign_row ~= sign_row or placed.sym_hl ~= sym_hl or placed.sym ~= state.sym then
                vim.api.nvim_buf_set_extmark(main_buffer, ns_id, sign_row, 0, {
                    id = pin.mark_pin_id,
                    sign_text = state.sym,
                    sign_hl_group = sym_hl,
                    number_hl_group = sym_hl,
                    priority = 100,
                    right_gravity = false
                })
                pin.placed.sign_row, pin.placed.sym_hl, pin.placed.sym = sign_row, sym_hl, state.sym
            end

            if pin_top <= top_stack then
                top_stack = top_stack + vis_h
            end
            if pin_bottom >= bottom then
                bottom = bottom - vis_h
                bottom_stack = bottom_stack + vis_h
            end
        end
    end

    local scrolloff = M.scrolloff + math.max(top_stack+2, bottom_stack+2)
    if vim.api.nvim_get_option_value("scrolloff", {win=anchor}) ~= scrolloff then
        vim.api.nvim_set_option_value("scrolloff", scrolloff, {win=anchor})
    end
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

-- index is optional, it falls back to the pin under the cursor and then to the
-- most recent pin, which is what :PinPop and friends expect
function M.pin_remove(index)
    if #M.pins == 0 then
        vim.notify("No pins to delete!")
        return
    end

    if index == nil then
        local ctx = M.context()
        index = M.pin_at_lnum(ctx.buf, ctx.lnum) or #M.pins
    end

    local pin = M.pins[index]

    if not pin then
        vim.notify("Pin " .. tostring(index) .. " not found")
        return
    end

    -- closing the pin window drops the cursor into some arbitrary window, keep
    -- the user in the main window instead
    if vim.api.nvim_get_current_win() == pin.win_id then
        vim.api.nvim_set_current_win(anchor_window())
    end

    if vim.api.nvim_win_is_valid(pin.win_id) then
        vim.api.nvim_win_close(pin.win_id, true)
    end
    if vim.api.nvim_buf_is_valid(pin.buf_id) then
        pcall(vim.api.nvim_buf_delete, pin.buf_id, { force = true })
    end

    if pin.mark_pin_id and vim.api.nvim_buf_is_valid(pin.source_buf) then
        pcall(vim.api.nvim_buf_del_extmark, pin.source_buf, ns_id, pin.mark_pin_id)
    end

    table.remove(M.pins, index)
    if M.focused_id then
        if M.focused_id > index then
            M.focused_id = M.focused_id - 1
        end
        if M.focused_id > #M.pins then
            M.focused_id = #M.pins > 0 and #M.pins or nil
        end
    end

    -- never pull the cursor into another pin just because it is under it now
    M.update_pin_position(false)
end

-- remove the pin covering a 0 indexed line of a source buffer
function M.remove_pin_at(bufnr, spos)
    local index = M.pin_at_lnum(bufnr, spos+1)
    if index then
        M.pin_remove(index)
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
    if not pin or not vim.api.nvim_win_is_valid(pin.win_id) then
        vim.notify("Pin " .. tostring(id) .. " not found")
        return
    end
    local anchor = anchor_window()
    vim.api.nvim_win_set_cursor(anchor, {pin.spos+1, 0})
    vim.api.nvim_set_current_win(pin.win_id)
    vim.api.nvim_win_set_cursor(pin.win_id, {1, 0})
    M.focused_id = id
end

function M.pin_focus_next()
    if #M.pins == 0 then
        vim.notify("No pins to jump to!")
        return
    end
    M.focused_id = (M.focused_id or 0) + 1
    local id = (M.focused_id > #M.pins) and 1 or M.focused_id
    M.pin_focus(id)
end

function M.pin_focus_prev()
    if #M.pins == 0 then
        vim.notify("No pins to jump to!")
        return
    end
    M.focused_id = (M.focused_id or #M.pins+1) - 1
    local id = (M.focused_id < 1) and #M.pins or M.focused_id
    M.pin_focus(id)
end

function M.create_pin(pin, lines)
    local source_buf = pin.source_buf or vim.api.nvim_get_current_buf()
    local anchor = anchor_window()

    -- create and populate the buffer for the pin
    local gutter_w, usable_width = get_layout_details(anchor)
    local float_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)

    local ft = vim.bo[source_buf].filetype
    vim.api.nvim_set_option_value('modifiable', true, {buf = float_buf})
    vim.api.nvim_set_option_value('filetype', ft, { buf = float_buf })
    -- copy fold settings so folds behave similarly inside pin
    pcall(function()
        local fm = vim.bo[source_buf].foldmethod
        if fm and fm ~= '' then
            vim.api.nvim_set_option_value('foldmethod', fm, {buf = float_buf})
        end
        local fe = vim.bo[source_buf].foldexpr
        if fe and fe ~= '' then
            vim.api.nvim_set_option_value('foldexpr', fe, {buf = float_buf})
        end
        local fcs = vim.bo[source_buf].foldcolumn
        if fcs then
            vim.api.nvim_set_option_value('foldcolumn', fcs, {buf = float_buf})
        end
        local fdn = vim.bo[source_buf].foldenable
        vim.api.nvim_set_option_value('foldenable', fdn, {buf = float_buf})
    end)
    pcall(vim.treesitter.start, float_buf, ft)

    pin.mark_pin_id = vim.api.nvim_buf_set_extmark(source_buf, ns_id, pin.spos, 0, {})

    -- open the floating window with the buffer
    local win_id = vim.api.nvim_open_win(float_buf, false, {
        relative = 'win',
        win = anchor,
        style = 'minimal',
        bufpos = {pin.spos, 0},
        width = usable_width,
        height = #lines,
        border = 'none',-- M.config.border,
        title = " Pin " .. (#M.pins +1),
        title_pos = "right",
        focusable = false,
    })
    vim.api.nvim_set_option_value("winhighlight",
        "Normal:pinvim_window_unlocked," ..
        "FloatBorder:pinvim_window_locked",
        {win=win_id}
    )
    vim.api.nvim_set_option_value("scrolloff", 1, {win=win_id})

    -- populate and push pin to storage
    pin.win_id = win_id
    pin.buf_id = float_buf
    pin.source_buf = source_buf
    pin.height = #lines
    table.insert(M.pins, pin)
    M.focused_id = #M.pins

    vim.keymap.set('n', 'j', function ()
        local row,col = unpack(vim.api.nvim_win_get_cursor(pin.win_id))
        if row == pin.height then
            local anchor = anchor_window()
            vim.api.nvim_set_current_win(anchor)
            vim.api.nvim_win_set_cursor(anchor, {pin.spos+pin.height+1, col})
        else
            vim.api.nvim_feedkeys('j', 'n', false)
        end
    end, { buffer = float_buf, silent = true })

    vim.keymap.set('n', 'k', function ()
        local row,col = unpack(vim.api.nvim_win_get_cursor(0))
        if row == 1 then
            local anchor = anchor_window()
            vim.api.nvim_set_current_win(anchor)
            vim.api.nvim_win_set_cursor(anchor, {pin.spos, col})
        else
            vim.api.nvim_feedkeys('k', 'n', false)
        end
    end, { buffer = float_buf, silent = true })

    vim.keymap.set('n', 'G', function()
        vim.api.nvim_set_current_win(anchor_window())
        vim.cmd("normal! G")
    end, { buffer = float_buf, silent = true })

    vim.keymap.set('n', 'gg', function()
        vim.api.nvim_set_current_win(anchor_window())
        vim.cmd("normal! gg")
    end, { buffer = float_buf, silent = true })

    -- update layout when folds change inside the pin
    pcall(function()
        vim.api.nvim_create_autocmd({"FoldUpdated", "CursorMoved", "WinScrolled", "TextChanged", "TextChangedI", "ModeChanged", "BufWinEnter", "WinEnter"}, {
            buffer = float_buf,
            callback = function()
                vim.schedule(function()
                    M.update_pin_position(false)
                end)
            end,
        })
    end)

    vim.api.nvim_buf_attach(float_buf, false, {
        on_lines = function()
            if pin.is_syncing then return end
            pin.is_syncing = true

            vim.schedule(function()
                local new_lines = vim.api.nvim_buf_get_lines(float_buf, 0, -1, false)
                local new_height = #new_lines
                local old_height = pin.height
                local delta = new_height - old_height

                vim.api.nvim_buf_set_lines(
                    source_buf,
                    pin.spos,
                    pin.spos + old_height,
                    false,
                    new_lines
                )

                if delta ~= 0 then
                    for _,other in ipairs(M.pins) do
                        if other ~= pin and other.spos > pin.spos then
                            other.spos = other.spos + delta
                            other.epos = other.epos + delta
                        end
                    end
                end

                -- the pin covers its own lines, so it grows and shrinks with them
                pin.height = new_height
                pin.epos = pin.spos + new_height - 1
                pin.placed = nil

                pin.is_syncing = false
            end)
        end
    })

    M.update_pin_position(M.config.focus_on_create and true or false)
end

-- pin a range of a source buffer, from/to are 0 indexed and inclusive
function M.pin_range(bufnr, from, to)
    from, to = math.max(0, from), math.max(from, to)

    if not vim.api.nvim_buf_is_loaded(bufnr) then
        vim.notify("Pin source buffer is not loaded")
        return
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, from, to+1, false)
    if #lines == 0 then
        vim.notify("Nothing to pin")
        return
    end

    M.create_pin({
        win_id = nil,
        buf_id = nil,
        source_buf = bufnr,
        spos = from,
        epos = to,
        height = #lines
    }, lines)
end

-- every foldable block in a buffer, by indentation alone. this mirrors
-- nvim-ufo's indent provider so a pin lands on the same block `za` would fold,
-- which is the behaviour to match when a buffer has no tree-sitter parser.
-- levels are indent widths bucketed by shiftwidth, blank lines get -1 so they
-- belong to no level and simply do not close the blocks they sit inside
local function indent_levels(lines, tabstop, shiftwidth)
    local levels = {}
    for i, line in ipairs(lines) do
        local width, level = 0, -1
        for col = 1, #line do
            local b = line:byte(col, col)
            if b == 0x20 then
                width = width + 1
            elseif b == 0x09 then
                width = width + (tabstop - (width % tabstop))
            else
                level = math.ceil(width / shiftwidth)
                break
            end
        end
        levels[i] = level
    end
    return levels
end

local function indent_folds(levels)
    local folds, stack = {}, {}

    -- a stack entry is the header line of a block still open. walking back up
    -- the indentation levels closes every block at or below the level just left
    local function close(cur_level, last_lnum)
        while #stack > 0 do
            local open = stack[#stack]
            if open.level >= cur_level then
                folds[#folds+1] = {open.lnum, last_lnum}
                stack[#stack] = nil
            else
                break
            end
        end
    end

    local last_lnum, last_level = 1, levels[1]
    for i = 1, #levels do
        local level = levels[i]
        if level >= 0 then
            -- indented past the line above, so that line opens a block
            if level > 0 and level > last_level then
                stack[#stack+1] = {level = last_level, lnum = last_lnum}
            elseif level < last_level then
                close(level, last_lnum)
            end
            last_level, last_lnum = level, i
        end
    end
    close(0, last_lnum)

    return folds
end

-- the smallest block covering lnum, so the cursor on a nested body picks that
-- body rather than the whole function around it
local function indent_range(bufnr, lnum)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    if #lines == 0 then return nil end

    local tabstop = vim.api.nvim_get_option_value('tabstop', {buf = bufnr})
    if tabstop == 0 then tabstop = 8 end

    local shiftwidth = vim.api.nvim_get_option_value('shiftwidth', {buf = bufnr})
    if shiftwidth == 0 then shiftwidth = tabstop end

    local folds = indent_folds(indent_levels(lines, tabstop, shiftwidth))
    if #folds == 0 then return nil end

    local best
    for _, fold in ipairs(folds) do
        if lnum >= fold[1] and lnum <= fold[2] then
            -- ties go to the block starting later, which is the inner one
            if not best or fold[1] > best[1] or (fold[1] == best[1] and fold[2] < best[2]) then
                best = fold
            end
        end
    end

    -- nothing encloses the cursor, it is on a top level line of its own
    if not best then return nil end

    return best[1]-1, best[2]-1
end

-- the smallest named node around lnum/col which covers more than one line.
-- get_node on its own hands back the token under the cursor, which pins a
-- single line, and the buffer root when the cursor sits on blank space, which
-- pins the whole file. both are useless as a pin.
local function ts_node_range(bufnr, lnum, col)
    local node = vim.treesitter.get_node({ buf = bufnr, bufnr = bufnr, pos = { lnum-1, col } })
    if not node then return nil end

    -- the root spans the whole buffer, so a blank line or a position no node
    -- covers would otherwise pin the entire file. a parentless node is the
    -- only reliable way to spot it, its end row stops at the last line with
    -- content and so does not line up with the line count
    if not node:parent() then return lnum-1, lnum-1 end

    -- node:range is start_row, start_col, end_row, end_col, only the rows matter
    local from, _, to = node:range()
    while from == to and node:parent() do
        local parent = node:parent()
        local pfrom, _, pto = parent:range()
        node, from, to = parent, pfrom, pto
    end

    -- ran out of parents before hitting anything wider than the cursor line
    if not node:parent() then return lnum-1, lnum-1 end

    return from, to
end

-- tree-sitter when the buffer has a parser, indentation when it does not. this
-- mirrors the provider order nvim-ufo folds with, so pinning picks the same
-- block folding would regardless of which parsers happen to be installed
local function scope_range(bufnr, lnum, col)
    local found, parser = pcall(vim.treesitter.get_parser, bufnr)

    if found and parser then
        -- the parser fills in lazily, a node is only there once the tree is built
        pcall(function() parser:parse(true) end)

        local from, to = ts_node_range(bufnr, lnum, col)
        if from then return from, to end
    end

    return indent_range(bufnr, lnum)
end

function M.pin_scope()
    local ctx = M.context()
    local col = ctx.pin and 0 or vim.api.nvim_win_get_cursor(ctx.win)[2]

    local from, to = scope_range(ctx.buf, ctx.lnum, col)
    if not from then
        vim.notify("Nothing to pin at cursor")
        return
    end

    M.pin_range(ctx.buf, from, to)
end

function M.pin_ts_node()
    local ctx = M.context()

    -- a missing parser raises rather than returning nil, so both the guard and
    -- the value the call would have returned have to be checked
    local found, parser = pcall(vim.treesitter.get_parser, ctx.buf)
    if not (found and parser) then
        vim.notify("No tree-sitter parser for this buffer")
        return
    end

    -- the parser fills in lazily, a node is only there once the tree is built
    pcall(function() parser:parse(true) end)

    local col = ctx.pin and 0 or vim.api.nvim_win_get_cursor(ctx.win)[2]
    local from, to = ts_node_range(ctx.buf, ctx.lnum, col)
    if not from then
        vim.notify("No tree-sitter node at cursor")
        return
    end

    M.pin_range(ctx.buf, from, to)
end

-- <leader>ss in normal mode: get rid of the pin under the cursor, otherwise pin
-- the block at the cursor
function M.pin_toggle()
    local ctx = M.context()
    local idx = M.pin_at_lnum(ctx.buf, ctx.lnum)

    if idx then
        M.pin_remove(idx)
    else
        M.pin_scope()
    end
end

function M.pin_visual_selection()
    local ctx = M.context()

    -- '< and '> live in the buffer the selection was made in. when that is a
    -- pin they are pin relative and have to be shifted onto the source buffer.
    local from = vim.fn.getpos("'<")[2]
    local to = vim.fn.getpos("'>")[2]
    from, to = math.min(from, to), math.max(from, to)

    local base = ctx.pin and ctx.pin.spos or 0
    M.pin_range(ctx.buf, base+from-1, base+to-1)
end

vim.schedule(function()
    if not did_setup then
        M.setup()
    end
end)

return M
