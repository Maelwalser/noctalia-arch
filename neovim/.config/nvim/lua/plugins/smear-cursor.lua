-- Smear cursor — palette-consistent, snappy, scoped to real content buffers.
-- Cursor hue and trail highlight are sourced from `config.palette` so they
-- track the Nordic-cyberpunk theme; a ColorScheme autocmd re-applies them
-- on theme reload.
return {
  "sphamba/smear-cursor.nvim",
  event = "VeryLazy",
  config = function()
    local p = require("config.palette")

    -- Dedicated highlight group for the smear trail. Using a non-shared
    -- group means we can recolor it without affecting diagnostics / NonText.
    local function apply_hl()
      vim.api.nvim_set_hl(0, "SmearCursor", { fg = p.cyan, bg = "NONE" })
    end
    apply_hl()
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("SmearCursorHl", { clear = true }),
      callback = apply_hl,
    })

    require("smear_cursor").setup({
      -- Performance: sharper glyphs + modest tick rate
      legacy_computing_symbols_support = true,
      time_interval = 17, -- ~60fps; bump to 25+ on slow terms
      scroll_buffer_space = true,

      -- Motion feel (slightly snappier than defaults to match the
      -- "quiet but responsive" Nordic editor feel)
      stiffness                      = 0.8,
      trailing_stiffness             = 0.6,
      stiffness_insert_mode          = 0.7,
      trailing_stiffness_insert_mode = 0.7,
      trailing_exponent              = 2,
      distance_stop_animating        = 0.3,
      min_horizontal_distance_smear  = 2,
      min_vertical_distance_smear    = 2,

      -- Where to smear
      smear_horizontally           = true,
      smear_vertically             = true,
      smear_diagonally             = true,
      smear_insert_mode            = true,
      smear_to_cmd                 = true,
      smear_between_buffers        = true,
      smear_between_neighbor_lines = true,
      smear_terminal_mode          = false, -- off: fights terminal cursor

      -- Draw safety
      never_draw_over_target = true,

      -- Style: cyan cursor head + cyan smear trail
      cursor_color = p.cyan,
      hlgroup      = "SmearCursor",

      -- Disable in UI chrome, pickers, floating overlays, and lists where
      -- the smear adds noise rather than polish.
      disabled_buftypes = { "terminal", "nofile", "quickfix", "prompt", "help" },
      filetypes_disabled = {
        "alpha",
        "dashboard",
        "snacks_dashboard",
        "snacks_terminal",
        "snacks_picker_list",
        "snacks_picker_input",
        "lazy",
        "mason",
        "help",
        "terminal",
        "trouble",
        "Trouble",
        "TelescopePrompt",
        "TelescopeResults",
        "TelescopePreview",
        "noice",
        "notify",
        "oil",
        "NvimTree",
        "neo-tree",
        "qf",
      },
    })
  end,
}
