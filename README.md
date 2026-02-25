# pin.nvim

A plugin for pinning visual selection or tree-sitter nodes. Pins are kept visible so that you can still view them while comparing one part of a file to another for example. Editing within a pin is seemless and integrated as portals to the main buffer giving a good flow.

<img width="961" height="1048" alt="image" src="https://github.com/user-attachments/assets/e5c093bd-5993-4134-aae4-2de7b1fd6227" />

## 📌 Features
- ✓ Customizable icons, foreground color and background color for the states:
    - locked 🔒
    - unlocked 🔓
    - pinned 📌
- ✓ Customizable keybindings for:
    - 🌳 Pin tree sitter node
    - 👀 Pin visual selection
    - 🖈 Remove current pin
    - 🗑 Remove all pins
    -  🔢 Remove pin interactively
    -  ⎘ Jump to next pin
    -  ⎗ Jump to previous pin
    -  🔢 Jump to pin interactively
- ✓ Editible pins and a good flow working with pins

## 📦 Installation
Install the plugin with your preferred package manager:

lazy.nvim:
```lua
{
    "qrikko/pin.nvim",
    config = function()
    end
}
```

## ⚙️ Configuration
<details>
  <summary>These are the default config which all should be overridable in your config</summary>
  
  ```lua
  {
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
```
</details>

