# 🗺️ nvim-navbuddy

A simple popup display that provides breadcrumbs like navigation feature but
in keyboard centric manner inspired by ranger file manager.

https://user-images.githubusercontent.com/43147494/227758807-13a614ff-a09d-4be0-8f6b-ac22f814ce6f.mp4

## ⚡️ Requirements

* Neovim >= 0.10.0
* [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)
* [nvim-navic](https://github.com/SmiteshP/nvim-navic)

## 📦 Installation

Install the plugin with your preferred package manager:

### [packer](https://github.com/wbthomason/packer.nvim)

```lua
use {
    "SmiteshP/nvim-navbuddy",
    requires = {
        "neovim/nvim-lspconfig",
        "SmiteshP/nvim-navic",
        "numToStr/Comment.nvim",        -- Optional
        "nvim-telescope/telescope.nvim" -- Optional
    }
}
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug "neovim/nvim-lspconfig"
Plug "SmiteshP/nvim-navic"
Plug "numToStr/Comment.nvim",        " Optional
Plug "nvim-telescope/telescope.nvim" " Optional
Plug "SmiteshP/nvim-navbuddy"
```

### Lazy Loading

If you want to lazy load navbuddy you need to load it before your Lsp related Stuff.

For Example with [Lazy](https://github.com/folke/lazy.nvim) and [lspconfig](https://github.com/neovim/nvim-lspconfig)

```lua
return {
    "neovim/nvim-lspconfig",
    dependencies = {
        {
            "SmiteshP/nvim-navbuddy",
            dependencies = {
                "SmiteshP/nvim-navic",
            },
            opts = { lsp = { auto_attach = true } }
        }
    },
    -- your lsp config or other stuff
}
```

## ⚙️ Setup

nvim-navbuddy needs to be attached to lsp servers of the buffer to work. You can pass the
navbuddy's `attach` function as `on_attach` while setting up the lsp server. You can skip this
step if you have enabled `auto_attach` option in setup function.

Example:
```lua
local navbuddy = require("nvim-navbuddy")

require("lspconfig").clangd.setup {
    on_attach = function(client, bufnr)
        navbuddy.attach(client, bufnr)
    end
}
```

## 🪄 Customise

Use `setup` to override any of the default options

* `icons` : Indicate the type of symbol captured. Default icons assume you have nerd-fonts.
* `node_markers` : Indicate whether a node is a leaf or branch node. Default icons assume you have nerd-fonts.
* `window` : Set options related to the navbuddy strip — its `height`, `scrolloff`, and per-section `width` / `win_options` / `buf_options`.
* `use_default_mappings`: If set to false, only mappings set by user are set. Else default mappings are used for keys that are not set by user.
* `mappings` : Actions to be triggered for specified keybindings. For each keybinding it takes a table of format { callback = <function_to_be_called>, description = "string"}. The callback function takes the "display" object as an argument.
* `lsp` :
    * `auto_attach` : Enable to have Navbuddy automatically attach to every LSP for current buffer. Its disabled by default.
    * `preference` : Table ranking lsp_servers. Lower the index, higher the priority of the server. If there are more than one server attached to a buffer, navbuddy will refer to this list to make a decision on which one to use. for example - In case a buffer is attached to clangd and ccls both and the preference list is `{ "clangd", "pyright" }`. Then clangd will be prefered.
* `workspace` :
    * `enabled` : Enable workspace-scope navigation across files in the LSP workspace roots. Default `true`.
    * `default_scope` : `"auto"` (workspace if any LSP exposes one, else buffer), `"workspace"` (error if no workspace LSP), or `"buffer"`. Default `"auto"`.
    * `max_files` : Hard cap on the workspace file scan. Default `5000`. A warning is shown if hit.
    * `exclude_dirs` : Directory basenames skipped during the scan. Default includes `.git`, `node_modules`, `target`, `build`, `dist`, etc.
    * `cache` : Reuse a single workspace tree across invocations. Symbol entries are invalidated on `BufWritePost` of the corresponding file. Default `false`.
* `source_buffer` :
    * `follow_node` : Keep the current node in focus on the source buffer
    * `highlight` : Highlight the currently focused node
    * reorient: Reorient buffer after changing nodes. options are "smart", "top", "mid" or "none"

```lua
local navbuddy = require("nvim-navbuddy")
local actions = require("nvim-navbuddy.actions")

navbuddy.setup {
    window = {
        height = "50%",       -- Height of the navbuddy strip ("NN%" of &lines, or absolute int).
        scrolloff = nil,      -- scrolloff value inside the navbuddy MID window
        sections = {
            left = {
                width = "20%",  -- Width of LEFT pane ("NN%" of &columns, or absolute int).
                win_options = nil,
                buf_options = nil,
            },
            mid = {
                win_options = nil,
                buf_options = nil,
            },
        },
    },
    node_markers = {
        enabled = true,
        icons = {
            leaf = "  ",
            leaf_selected = " → ",
            branch = " ",
        },
    },
    icons = {
        File          = "󰈙 ",
        Module        = " ",
        Namespace     = "󰌗 ",
        Package       = " ",
        Class         = "󰌗 ",
        Method        = "󰆧 ",
        Property      = " ",
        Field         = " ",
        Constructor   = " ",
        Enum          = "󰕘",
        Interface     = "󰕘",
        Function      = "󰊕 ",
        Variable      = "󰆧 ",
        Constant      = "󰏿 ",
        String        = " ",
        Number        = "󰎠 ",
        Boolean       = "◩ ",
        Array         = "󰅪 ",
        Object        = "󰅩 ",
        Key           = "󰌋 ",
        Null          = "󰟢 ",
        EnumMember    = " ",
        Struct        = "󰌗 ",
        Event         = " ",
        Operator      = "󰆕 ",
        TypeParameter = "󰊄 ",
    },
    use_default_mappings = true,            -- If set to false, only mappings set
                                            -- by user are set. Else default
                                            -- mappings are used for keys
                                            -- that are not set by user
    mappings = {
        ["<esc>"] = actions.close(),        -- Close and cursor to original location
        ["q"] = actions.close(),

        ["j"] = actions.next_sibling(),     -- down
        ["k"] = actions.previous_sibling(), -- up

        ["h"] = actions.parent(),           -- Move to left panel
        ["l"] = actions.children(),         -- Move to right panel
        ["0"] = actions.root(),             -- Move to first panel

        ["v"] = actions.visual_name(),      -- Visual selection of name
        ["V"] = actions.visual_scope(),     -- Visual selection of scope

        ["y"] = actions.yank_name(),        -- Yank the name to system clipboard "+
        ["Y"] = actions.yank_scope(),       -- Yank the scope to system clipboard "+

        ["i"] = actions.insert_name(),      -- Insert at start of name
        ["I"] = actions.insert_scope(),     -- Insert at start of scope

        ["a"] = actions.append_name(),      -- Insert at end of name
        ["A"] = actions.append_scope(),     -- Insert at end of scope

        ["r"] = actions.rename(),           -- Rename currently focused symbol

        ["d"] = actions.delete(),           -- Delete scope

        ["f"] = actions.fold_create(),      -- Create fold of current scope
        ["F"] = actions.fold_delete(),      -- Delete fold of current scope

        ["c"] = actions.comment(),          -- Comment out current scope

        ["<enter>"] = actions.select(),     -- Goto selected symbol
        ["o"] = actions.select(),

        ["J"] = actions.move_down(),        -- Move focused node down
        ["K"] = actions.move_up(),          -- Move focused node up

        ["<C-v>"] = actions.vsplit(),       -- Open selected node in a vertical split
        ["<C-s>"] = actions.hsplit(),       -- Open selected node in a horizontal split

        ["t"] = actions.telescope({         -- Fuzzy finder at current level.
            layout_config = {               -- All options that can be
                height = 0.60,              -- passed to telescope.nvim's
                width = 0.60,               -- default can be passed here.
                prompt_position = "top",
                preview_width = 0.50
            },
            layout_strategy = "horizontal"
        }),

        ["g?"] = actions.help(),            -- Open mappings help window
    },
    lsp = {
        auto_attach = false,   -- If set to true, you don't need to manually use attach function
        preference = nil,      -- list of lsp server names in order of preference
    },
    workspace = {
        enabled = true,
        default_scope = "auto",  -- "auto" | "workspace" | "buffer"
        max_files = 5000,
        exclude_dirs = {
            ".git", ".hg", ".svn",
            "node_modules", ".direnv", "result",
            "target", "build", "dist", "coverage",
        },
        cache = false,           -- Reuse workspace tree across invocations
    },
    source_buffer = {
        follow_node = true,    -- Keep the current node in focus on the source buffer
        highlight = true,      -- Highlight the currently focused node
        reorient = "smart",    -- "smart", "top", "mid" or "none"
        scrolloff = nil        -- scrolloff value when navbuddy is open
    },
	custom_hl_group = nil,     -- "Visual" or any other hl group to use instead of inverted colors
}
```

## 🚀 Usage

`Navbuddy` command opens navbuddy. By default the scope is `workspace.default_scope` (auto).

```
:Navbuddy             " Use configured default scope
:Navbuddy buffer      " Force buffer-only navigation (symbols in current file)
:Navbuddy workspace   " Force workspace navigation (directory tree + lazy symbol load)
:Navbuddy root        " Open at the workspace root (only with workspace scope)
```

And alternatively lua function `open` can also be used:

```
:lua require("nvim-navbuddy").open()                       -- default scope
:lua require("nvim-navbuddy").open({ scope = "workspace" })
:lua require("nvim-navbuddy").open({ scope = "buffer" })
```

### Workspace navigation

In workspace scope, navbuddy walks the LSP client's workspace roots, presenting
directories and files alongside symbols. Selecting a directory drills in;
selecting a file lazily fetches that file's symbols via
`textDocument/documentSymbol` and lets you continue into them. The current
file is auto-focused at the closest symbol to your cursor.

Tune behavior with `workspace.max_files`, `workspace.exclude_dirs`, and
`workspace.cache`. On large monorepos the cache is recommended; it survives
across invocations and is invalidated per-file on save.

