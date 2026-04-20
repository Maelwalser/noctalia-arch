-- Smooth viewport scrolling via cinnamon.nvim (v2).
--
-- Philosophy:
--   • j/k/h/l and arrows are NEVER wrapped by cinnamon — held motion goes
--     at native Vim speed (instant, zero per-keypress overhead).
--   • Only large jumps (<C-d>, <C-u>, <C-f>, <C-b>, gg, G, zz/zt/zb,
--     search next/prev, paragraph motion, %) glide through cinnamon so
--     the viewport reveals the target with a smooth acceleration curve.
--   • Cursor itself is never animated (`mode = "window"`).
--
-- Why `basic = false`: enabling the built-in basic keymaps wraps j/k/h/l
-- through cinnamon's scroll() even with count_only skipping the animation.
-- That still runs view-capture + bookkeeping on every keystroke, so holding
-- j/k feels noticeably slower than stock Vim. Skipping basic and mapping
-- only the big-jump keys keeps held motion snappy.
return {
  "declancm/cinnamon.nvim",
  event = "VeryLazy",
  config = function()
    local cinnamon = require("cinnamon")

    cinnamon.setup({
      keymaps = {
        basic = false, -- leave j/k/h/l/arrows native-fast
        extra = false,
      },
      options = {
        mode = "window",    -- cursor jumps; only viewport glides
        delay = 0,          -- no startup delay
        max_delta = {
          line = false,
          column = false,
          time = 220,       -- animation budget for big jumps
        },
        step_size = {
          vertical = 1,     -- finest granularity → smoothest easing curve
          horizontal = 2,
        },
        count_only = false,
      },
    })

    -- Animate only the motions that meaningfully shift the viewport.
    -- Small motions (j/k/h/l/w/b/etc.) stay native.
    local scroll = cinnamon.scroll
    local map = function(lhs, cmd)
      vim.keymap.set({ "n", "x" }, lhs, function() scroll(cmd) end,
        { silent = true, desc = "Cinnamon: " .. cmd })
    end

    -- Half / full page
    map("<C-d>", "<C-d>")
    map("<C-u>", "<C-u>")
    map("<C-f>", "<C-f>")
    map("<C-b>", "<C-b>")
    -- File jumps
    map("gg", "gg")
    map("G", "G")
    -- Recenter
    map("zz", "zz")
    map("zt", "zt")
    map("zb", "zb")
    -- Search / match jumps
    map("n", "n")
    map("N", "N")
    map("*", "*")
    map("#", "#")
    map("%", "%")
    -- Paragraph jumps
    map("{", "{")
    map("}", "}")
  end,
}
