return {
    "declancm/cinnamon.nvim",
    event = "VeryLazy", -- Load it lazily
    opts = {
        keymaps = {
            basic = true,
            extra = false,
        },
    -- Window-only mode is fastest
    options = {
      mode = "window",
        }
    },
    config = function(_, opts)
        require("cinnamon").setup({
            opts,
            enabled = true,

            show_scrollbars = true,
            --
            -- Default: { "alpha", "beta", "diff", "dropbar", "fugitive", "gitcommit", "help", "hgcommit", "log", "markdown", "NvimTree", "Outline", "quickfix", "git", "neo-tree" }
            -- excluded_filetypes = { "neo-tree", "NvimTree", "Trouble", "lazy", "mason", "help", "alpha", "dashboard" },
            -- Maximum width of the scrollbar.
            use_window_highlight = false,
            
            -- Highlight group for the scrollbar.
            -- Default: "Visual"
            scrollbar_highlight = "CursorLineNr", -- Or "Visual", "ColorColumn"
            
            -- Highlight group for the scrollbar handle.
            -- Default: "Search"
            thumb_highlight = "PmenuSel", -- Or "Search", "Visual"

            smooth_scroll = true,
            -- Configuration for smooth scrolling.
            smooth_scroll_config = {
                
                -- Duration of the smooth scroll animation in milliseconds.
                -- Default: 200
                duration = 100,
                
                -- Interval between scroll steps in milliseconds.
                -- Default: 10
                interval = 5,
                
                -- Easing function for the smooth scroll animation.
                -- Available options: "linear", "ease_in_quad", "ease_out_quad", "ease_in_out_quad",
                -- "ease_in_cubic", "ease_out_cubic", "ease_in_out_cubic", "ease_in_quart", "ease_out_quart",
                -- "ease_in_out_quart", "ease_in_quint", "ease_out_quint", "ease_in_out_quint"
                -- Default: "ease_out_quad"
                easing = "ease_out_quad",
            },

            -- Whether to show diagnostics on the scrollbar.
            -- Default: true
            show_diagnostics = true,

            -- Highlight group for error diagnostics on the scrollbar.
            -- Default: "DiagnosticError"
            error_highlight = "DiagnosticSignError",

            -- Highlight group for warning diagnostics on the scrollbar.
            -- Default: "DiagnosticWarn"
            warn_highlight = "DiagnosticSignWarn",

            -- Highlight group for info diagnostics on the scrollbar.
            -- Default: "DiagnosticInfo"
            info_highlight = "DiagnosticSignInfo",

            -- Highlight group for hint diagnostics on the scrollbar.
            -- Default: "DiagnosticHint"
            hint_highlight = "DiagnosticSignHint",

            delay_ms = 30,

            -- Maximum number of lines to render on the scrollbar.
            -- Default: nil (no limit)
            max_length = nil,

            -- Priority of the extmark used for the scrollbar.
            -- Default: 100
            priority = 100,

            -- Z-index of the floating window used for the scrollbar.
            -- Default: 100
            z_index = 100,

            -- Whether to override the default keymaps for scrolling.
            -- Default: true
            override_default_keymaps = true,

        })
    end
    
    --     opts = {
    --         delay = 5,
    --         max_delta = {
    --             -- Maximum distance for line movements before scroll
    --             -- animation is skipped. Set to `false` to disable
    --             line = false,
    --             -- Maximum distance for column movements before scroll
    --             -- animation is skipped. Set to `false` to disable
    --             column = false,
    --             -- Maximum duration for a movement (in ms). Automatically scales the
    --             -- delay and step size
    --             time = 1000,
    --         },

    --         step_size = {
    --             -- Number of cursor/window lines moved per step
    --             vertical = 1,
    --             -- Number of cursor/window columns moved per step
    --             horizontal = 2,
    --         },
    --         keymaps = {
    --             basic = true,
    --             extra = true,
    --         },
    --         mode = "cursor",
    --         -- step_size = {
    --         --     vertical = 7,
    --         --     horizontal = 8,
    --         -- },
    --         -- max_delta = {
    --         --     time = 400,
    --         -- },
    --     },
}
