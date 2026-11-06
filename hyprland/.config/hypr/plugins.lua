-- Third-party plugins, built from pinned commits by `hypr-plugins`
-- (hyprland/.local/bin) into ~/.local/share/hyprland/plugins. A missing build
-- is skipped, so a fresh machine starts fine before the first build.
local dir = os.getenv("HOME") .. "/.local/share/hyprland/plugins/"

local function load(lib)
    local f = io.open(dir .. lib, "r")
    if not f then
        return
    end
    f:close()
    hl.plugin.load(dir .. lib)
end

-- confined-floats: floating windows cannot be dragged off-screen.
-- https://github.com/mennemann/hyprland-confined-floats
load("libconfined-floats.so")
if hl.plugin.confined_floats ~= nil then
    hl.window_rule({
        match = { class = ".*" },
        ["confined-floats:confine"] = true,
    })
end

-- hyprglass: Liquid Glass (blur, edge refraction, specular rim) on layers.
-- https://github.com/hyprnux/hyprglass
-- ACID//HUD only: the notification toasts become clear glass. Noctalia keeps
-- their fill nearly transparent (themes/acid.toml) so this is what shows.
load("hyprglass.so")
if hl.plugin.hyprglass ~= nil then
    local hg = hl.plugin.hyprglass
    local acid = require("dotfiles_theme") == "acid"
    -- enabled = false: windows stay as they are (it defaults to glass on all).
    hg.config({ enabled = false, default_theme = "dark", layers = { enabled = acid } })
    if acid then
        -- iOS 26 Liquid Glass: milky, light glass over a softly blurred backdrop,
        -- a thin even rim all round, a soft top light at the upper edge and
        -- corners, and a narrow lens bend at the rim with barely any rainbow.
        hg.preset("acid_clear", {
            inherits = "pomme",
            blur_strength = 0.4,
            blur_iterations = 2,
            edge_thickness_px = 12,
            edge_height = 8,
            refraction_strength = 2.0,
            chromatic_aberration = 0.12,
            fresnel_strength = 0.08,
            specular_strength = 0.6,
            specular_angle = 0,
            bevel_strength = 0.2,
            bevel_angle = 0,
            bevel_size = 1.5,
            bevel_shadow = 0.0,
            dark = {
                tint_color = 0xdce6f010,
                brightness = 1.0,
                contrast = 0.95,
                saturation = 1.05,
                vibrancy = 0.1,
                adaptive_dim = 0.0,
                adaptive_boost = 0.0,
            },
        })
        -- contour: each stacked toast gets its own edge. The toast has no
        -- shadow, so the threshold sits just above zero; the feather is kept
        -- tiny because a scaled toast ends on a half-covered row whose alpha
        -- (~0.05) must still get the full glass, or the bottom rim fades out.
        hg.layer("noctalia-notification", { preset = "acid_clear", mask_mode = "contour", mask_threshold = 0.01, mask_feather = 0.03 })
    end
end
