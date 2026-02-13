local state = { visible = false }

local function create_pin(text)
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


local function get_visual_text(opts)
    local startln = opts.line1 - 1
    local endln = opts.line2

    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, startln, endln, false)

    return lines
end

local function get_ts_text()
    local ts_utils = require('nvim-treesitter.ts_utils')
    local node = ts_utils.get_node_at_cursor()

    if not node then return end

    local bufnr = vim.api.nvim_get_current_buf()
    local text = vim.treesitter.get_node_text(node, bufnr)

    return text
end

vim.api.nvim_create_user_command('PinVisualSelection', function(opts)
    local text = get_visual_text(opts)
    create_pin(text)
end, { nargs = 0, range = true})

vim.api.nvim_create_user_command('PinTSNode', function()
    local text = get_ts_text()
    create_pin(text)
end, {})
