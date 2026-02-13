local state = { visible = false }

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

local function pin_selection()
        local sel = get_visual_selection()
end

local function pin_ts_node()
    local ts_utils = require('nvim-treesitter.ts_utils')
    local node = ts_utils.get_node_at_cursor()

    if not node then return end

    -- Get the actual text of the node
    local bufnr = vim.api.nvim_get_current_buf()
    local text = vim.treesitter.get_node_text(node, bufnr)
    local lines = vim.split(text, '\n')

    -- Create a scratch buffer for the popup
    local float_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value('filetype', vim.bo.filetype, { buf = float_buf })

    -- Open the window
    vim.api.nvim_open_win(float_buf, false, {
        relative = 'editor',
        row = 5,
        col = 5,
        width = 60,
        height = #lines + 2,
        style = 'minimal',
        border = 'rounded'
    })
end

vim.api.nvim_create_user_command('PinSelection', function() pin_selection() end, { nargs = 0, range = true})
vim.api.nvim_create_user_command('PinTSNode', pin_ts_node, {})
