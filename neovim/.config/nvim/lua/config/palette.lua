-- Nordic-cyberpunk palette.
-- Based on Nord's "same tonal family" philosophy — every accent sits in the
-- ~55% lightness / ~30% saturation band so no token competes visually —
-- paired with a darker, cooler bg than vanilla Nord so the editor still
-- reads "night-mode cyberpunk" rather than corporate-light.
--
-- Accent hues are assigned deliberately:
--   blue   → functions (who does what)
--   yellow → types     (what kind of thing)
--   purple → keywords  (structural verbs — control flow, storage)
--   cyan   → fields/properties/operators (access)
--   green  → strings, additions (calm)
--   orange → numbers, constants (warm literals)
--   pink   → escapes / exceptions / accents (rare pop)
--   red    → errors / deletions (reserved loud color)
return {
  -- Backgrounds (Polar Night family, deepened for night coding)
  bg         = "#14171f",
  bg_alt     = "#1c212d",
  bg_dim     = "#0f1218",
  bg_float   = "#1a1e28",
  cursorline = "#222838",
  selection  = "#2a3348", -- subtle: menu / picker selection
  visual     = "#384560", -- bright: visual-mode text selection
  indent     = "#1c2030",
  border     = "#2e3445", -- muted slate (darker than Nord polar-night 2)

  -- Foregrounds (Snow Storm family, slightly muted)
  fg         = "#d8dee9", -- Nord snow-storm 1
  fg_dim     = "#6a7694", -- line numbers, inactive, punctuation
  comment    = "#465068", -- comments: ~3:1 contrast so code reads louder

  -- Frost (cool accents)
  blue       = "#81a1c1", -- Nord frost 3 — functions
  cyan       = "#88c0d0", -- Nord frost 2 — fields / properties
  teal       = "#8fbcbb", -- Nord frost 1 — hints
  -- Aurora (warm accents, Nord-muted)
  yellow     = "#ebcb8b", -- Nord aurora yellow — types
  orange     = "#d08770", -- Nord aurora orange — numbers / constants
  green      = "#a3be8c", -- Nord aurora green — strings / add
  purple     = "#b48ead", -- Nord aurora purple — keywords
  magenta    = "#c9a3bc", -- softened purple — return / export
  pink       = "#d5919c", -- softened red — escapes / accents
  red        = "#bf616a", -- Nord aurora red — errors / delete
}
