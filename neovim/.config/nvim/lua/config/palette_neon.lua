-- Neon palette for the classic (eyes) theme: the colours the ACID//HUD theme
-- gave Neovim up to 2026-11-10, frozen here when ACID//HUD moved on to a
-- palette sampled from its wallpaper. Merged over the defaults in palette.lua;
-- keys mirror that file.
return {
  bg         = "#0b0712",
  bg_alt     = "#1a1226",
  bg_dim     = "#040307",
  bg_float   = "#1a1226",
  cursorline = "#1a1226",
  selection  = "#524567",
  visual     = "#53083e",
  indent     = "#1a1226",
  border     = "#66557f",

  fg         = "#efe7f4",
  fg_dim     = "#6a5a84",
  comment    = "#7a6597",

  blue       = "#ef5fc6", -- functions: the magenta accent
  cyan       = "#a8b0ff", -- fields / operators
  teal       = "#9ee0ec", -- hints
  yellow     = "#ffa35e", -- types
  orange     = "#ffc48f", -- numbers / constants
  green      = "#72c8d8", -- strings
  purple     = "#ef5fc6", -- keywords
  magenta    = "#ff8fdc", -- return / export
  pink       = "#b7a8c9", -- escapes: quiet
  red        = "#ff4d5e",
}
