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
-- ACID//HUD only: the notification toasts and the bar rail become clear glass.
-- Noctalia keeps their fill nearly transparent (themes/acid.toml) so this is
-- what shows.
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
        -- The bar rail is the same glass: its layer is taller than the rail
        -- (room Noctalia keeps for a shadow), so the contour traces the rail.
        -- The capsules inside it (themes/acid.toml, a translucent fill over the
        -- rail's) are nested shapes (patch 0003): each gets its own rim, bend
        -- and top light, a lens laid on the rail like iOS 26's selected tab.
        -- mask_nested sits between the rail's alpha (0.1) and the capsules'.
        hg.layer("noctalia-bar-default", { preset = "acid_clear", mask_mode = "contour", mask_threshold = 0.01, mask_feather = 0.03, mask_nested = 0.15 })
        -- Panels attached to the bar (control centre, session, wallpaper): in
        -- Noctalia's "glass" transparency mode the panel box is a faint rounded
        -- fill (alpha ~0.08) the size of its layer, so the toast settings fit.
        hg.layer("noctalia-attached-panel", { preset = "acid_clear", mask_mode = "contour", mask_threshold = 0.01, mask_feather = 0.03 })
        -- The desktop overlay's panes (quickshell hud, GlassScene.qml): faint
        -- rounded fills on their own layer, so each gets its own rim; the
        -- overlay's text stays on hud-overlay, which is not listed. Big panes
        -- over the wallpaper's soft lights: a stronger blur melts the scanlines
        -- and grid into the glow inside the pane, a wider, taller lens edge
        -- bends the lights visibly at the rim with more light on it, and a
        -- lighter tint than the toasts keeps the body from reading as a flat
        -- grey box against the rim.
        hg.preset("acid_pane", {
            inherits = "acid_clear",
            blur_strength = 0.55,
            edge_thickness_px = 22,
            edge_height = 14,
            refraction_strength = 2.6,
            specular_strength = 0.9,
            fresnel_strength = 0.12,
            dark = { tint_color = 0xdce6f00c },
        })
        hg.layer("hud-glass", { preset = "acid_pane", mask_mode = "contour", mask_threshold = 0.01, mask_feather = 0.03 })
        -- The unlock reveal (quickshell hud, UnlockFold.qml): the lock scene
        -- parts as two frosted glass doors. The layer's alpha is the door's
        -- presence, and the feather turns it into the blur's strength. Plain
        -- alpha mode, not contour: the contour is rebuilt on a timer and
        -- lagged the moving door into visible steps, and the shader draws the
        -- door's border itself. Below the threshold the shader only casts a
        -- soft shadow, which must stay sharp.
        hg.preset("acid_fold", {
            inherits = "acid_clear",
            blur_strength = 2.4,
            blur_iterations = 3,
            edge_thickness_px = 28,
            edge_height = 8,
            refraction_strength = 2.0,
            chromatic_aberration = 0.15,
            fresnel_strength = 0.12,
            specular_strength = 0.6,
            bevel_strength = 0.2,
            dark = {
                tint_color = 0xe8dcf510,  -- the frost's lavender, not the toasts' cool white
                brightness = 1.0,  -- the shader dims the desktop itself (glassDim)
            },
        })
        hg.layer("hud-unlock", { preset = "acid_fold", mask_mode = "alpha", mask_threshold = 0.12, mask_feather = 0.3 })
        -- The terminal is the same glass, a shade darker: a dark tint and a
        -- dim on bright windows behind it keep the text readable, the rim is
        -- an even fresnel glow plus the top bevel light, and the focused
        -- terminal gets a soft light all round its edge. Ghostty's own fill
        -- is lowered in ghostty/variants/acid.conf so the glass shows.
        hg.preset("acid_term", {
            inherits = "acid_clear",
            fresnel_strength = 0.22,
            focus_light = 0.35,
            dark = {
                tint_color = 0x0b0d0a40,
                brightness = 0.9,
                adaptive_dim = 0.3,
            },
        })
        hl.window_rule({ match = { class = "^com\\.mitchellh\\.ghostty$" }, tag = "+hyprglass_enabled" })
        hl.window_rule({ match = { class = "^com\\.mitchellh\\.ghostty$" }, tag = "+hyprglass_preset_acid_term" })
    end
end
