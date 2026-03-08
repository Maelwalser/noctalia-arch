return {
  "catgoose/nvim-colorizer.lua",
  event = "BufReadPre",
  config = function()
    require("colorizer").setup({
      filetypes = {
        -- Enable for all files with default config
        '*',
        -- specific configuration for Dart to handle Flutter colors
        dart = {
          AARRGGBB = true, -- specific option to handle 0xAARRGGBB
        },
      },
      user_default_options = {
        RGB = true,       -- #RGB hex codes
        RRGGBB = true,    -- #RRGGBB hex codes
        names = false,    -- Disable "Blue", "Red" names to reduce noise
        RRGGBBAA = false, -- Disable standard RGBA to avoid conflicts in Dart
        AARRGGBB = false, -- Default false globally, enabled specifically for Dart above
        rgb_fn = true,    -- CSS rgb() and rgba() functions
        hsl_fn = true,    -- CSS hsl() and hsla() functions
        css = false,      -- Enable all CSS features: rgb_fn, hsl_fn, names, RGB, RRGGBB
        css_fn = false,   -- Enable all CSS *functions*: rgb_fn, hsl_fn
        -- Available modes for `mode`: foreground, background,  virtualtext
        mode = "background", -- Set the display mode.
        -- Tailwind CSS lsp colors
        tailwind = false,
        sass = { enable = false, parsers = { "css" }, }, 
        virtualtext = "■",
      },
    })
  end,
}
