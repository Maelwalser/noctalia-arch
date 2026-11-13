-- Third-party plugins, built from pinned commits by `hypr-plugins`
-- (hyprland/.local/bin) into ~/.local/share/hyprland/plugins. A missing build
-- is skipped, so a fresh machine starts fine before the first build.
local dir = os.getenv("HOME") .. "/.local/share/hyprland/plugins/"

local function slurp(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local s = f:read("a")
    f:close()
    return s
end

-- A build for another Hyprland (e.g. right after a pacman upgrade) is skipped
-- too: hypr-plugins records the version.h it compiled against, and a stale
-- plugin would otherwise pop its red "version mismatch" notification over the
-- lock screen at every start and reload. Rerun hypr-plugins to bring them back.
local current = slurp(dir .. ".built-for") == slurp("/usr/include/hyprland/src/version.h")

local function load(lib)
    local f = current and io.open(dir .. lib, "r")
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

-- stackzoom: the zoomed-out work view on ALT + Tab (bindings.lua). Our own,
-- from hyprland/.local/share/hyprland/plugin-local/stackzoom.
load("stackzoom.so")

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
        -- The OSD pill takes the toast settings as it is.
        hg.layer("noctalia-osd", { preset = "acid_clear", mask_mode = "contour", mask_threshold = 0.01, mask_feather = 0.03 })
        -- The bar rail is the same glass: its layer is taller than the rail
        -- (room Noctalia keeps for a shadow), so the contour traces the rail.
        -- The capsules inside it (themes/acid.toml, a translucent fill over the
        -- rail's) are nested shapes (patch 0003): each gets its own rim, bend
        -- and top light, a lens laid on the rail like iOS 26's selected tab.
        -- mask_nested sits between the rail's alpha (0.1) and the capsules'.
        -- The rail is the clear glass of the desktop panes (acid_pane_clear
        -- below) with the toasts' narrow rim: no grey veil over the dark top
        -- of the wallpaper. It shows by its edge light, as the panes do.
        hg.preset("acid_rail", {
            inherits = "acid_clear",
            blur_strength = 0.5,
            dark = { tint_color = 0xdce6f007, contrast = 0.975 },
        })
        -- mask_join: a panel attached to the bar is the bar running on. Where
        -- the panel's shape touches the rail's bottom edge the rail has no
        -- edge.
        -- edge_light: the panes' edge light (quickshell hud, PaneLight.qml,
        -- rim 0.55), drawn by the plugin from the traced outline (patch
        -- 0005). The HUD drew it on a layer of its own over the rail, but it
        -- cannot know where a panel touches the rail on each frame of its
        -- slide; the outline does, so the line opens with the panel and runs
        -- on round its fillets without a break.
        -- nested_frost: the pills on the rail are blurred sections of the
        -- same sheet, not lenses of their own with a rim (patch 0006).
        hg.layer("noctalia-bar-default", { preset = "acid_rail", mask_mode = "contour", mask_threshold = 0.01, mask_feather = 0.03, mask_nested = 0.15, nested_frost = 3.0, mask_join = "noctalia-attached-panel", edge_light = 0.55 })
        -- Panels attached to the bar (control centre, session, wallpaper): in
        -- Noctalia's "glass" transparency mode the panel box is a faint rounded
        -- fill the size of its layer, traced like the toasts. A panel is the
        -- rail's glass flowing out downwards, so it takes the rail's preset as
        -- it is: any difference in blur, tint or rim shows as an edge where
        -- the two meet (a frosted sheet under the clear rail read as a second
        -- pane with a border; frosting the rail to match changed the bar on
        -- every open; a wider, brighter rim stepped where the panel's sides
        -- reach the rail; the user rejected each).
        -- mask_open: the sheet has no top edge. It hangs from the rail, whose
        -- glass it continues (mask_join above); the plugin then draws both
        -- from the same backdrop at the seam, so it is exact over any window.
        -- open_frost thickens the glass within 10 px into frosted glass:
        -- tiled windows start 16 px under the rail, and through clear glass
        -- their top border and the strip of wallpaper above it showed as a
        -- bright line under the bar, the "border" again. Frosted, they melt
        -- into a soft glow, and a terminal's text behind the sheet no longer
        -- fights the panel's own. No more than that: at 3.0 the sheet was a
        -- flat matte board, nothing like the rail's glass.
        -- mask_fillet: Noctalia slides the panel out from under the rail and
        -- shows its fillets (radius 22) only once it has arrived, so its
        -- sides met the rail in square corners all the way down and the
        -- curves popped in at the end. The plugin rounds those corners itself
        -- with the same radius, from the first frame: the sheet wells out of
        -- the rail in one shape, and nothing moves when Noctalia's own
        -- fillets arrive (measured: the same pixels).
        -- edge_light: the rail's, running on round the fillets, down the
        -- sides and along the bottom.
        -- The cards inside are Noctalia's own fills (62 % at the least, no
        -- option for less), so they stay darker insets on the sheet;
        -- mask_nested does not light them through a fill that dense.
        hg.layer("noctalia-attached-panel", { preset = "acid_rail", mask_mode = "contour", mask_threshold = 0.01, mask_feather = 0.03, mask_open = "top", open_frost = 1.5, open_feather = 10, mask_fillet = 22, edge_light = 0.55 })
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
        -- Over the wallpaper's near-black corners the tint and the softened
        -- contrast of acid_pane are all there is to see: a grey veil (body
        -- +17 over black, "milky"). About half of it here (the user found
        -- none at all "too much": a little frost has to stay); the panes draw
        -- their own edge light (quickshell hud, shaders/pane.frag).
        hg.preset("acid_pane_clear", {
            inherits = "acid_pane",
            blur_strength = 0.5,
            dark = { tint_color = 0xdce6f007, contrast = 0.975 },
        })
        hg.layer("hud-glass", { preset = "acid_pane_clear", mask_mode = "contour", mask_threshold = 0.01, mask_feather = 0.03 })
        -- The launcher (quickshell hud, Launcher.qml) opens over whatever is
        -- on screen, so it is the toasts' glass a shade darker, dimmed further
        -- over a bright window, to keep its text readable. The selected row
        -- is a nested lens, as the capsules are on the bar's rail.
        hg.preset("acid_launcher", {
            inherits = "acid_clear",
            blur_strength = 1.2,
            blur_iterations = 3,
            dark = { tint_color = 0x0b071270, brightness = 0.9, adaptive_dim = 0.35 },
        })
        hg.layer("hud-launcher-glass", { preset = "acid_launcher", mask_mode = "contour", mask_threshold = 0.01, mask_feather = 0.03, mask_nested = 0.15 })
        -- The bar's tooltips (quickshell hud, Tip.qml): the toasts' glass on a
        -- shape a quarter of their height, so the bent edge is halved (as it
        -- is for the bar's capsules) to leave a flat middle under the text,
        -- which a bright window behind it dims a little to stay readable.
        hg.preset("acid_tip", {
            inherits = "acid_clear",
            edge_thickness_px = 6,
            edge_height = 4,
            dark = { adaptive_dim = 0.3 },
        })
        hg.layer("hud-tooltip", { preset = "acid_tip", mask_mode = "contour", mask_threshold = 0.01, mask_feather = 0.03 })
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
        -- GTK4 / libadwaita apps (Nautilus, zenity dialogs) are the terminal's
        -- glass, frosted: their window fill is thinned in
        -- gtk/.config/gtk-4.0/variants/acid.css, and file lists are small
        -- text over whatever is behind, so the blur is well above the
        -- terminal's and bright backdrops are dimmed further.
        hg.preset("acid_app", {
            inherits = "acid_term",
            blur_strength = 1.0,
            blur_iterations = 3,
            dark = {
                tint_color = 0x0b071250,
                brightness = 0.9,
                adaptive_dim = 0.45,
            },
        })
        -- The same for what is still GTK3: the portal's file chooser and the
        -- passphrase prompt (gtk/.config/gtk-3.0/variants/acid.css).
        local gtk_apps = { class = "^(org\\.gnome\\..+|zenity|xdg-desktop-portal-gtk|gcr-prompter|pinentry.*)$" }
        hl.window_rule({ match = gtk_apps, tag = "+hyprglass_enabled" })
        hl.window_rule({ match = gtk_apps, tag = "+hyprglass_preset_acid_app" })
        -- Noctalia's Settings window is the desktop panes' glass, frosted: it
        -- is full of small text, which clear glass leaves unreadable over the
        -- wallpaper's neon signs, so the blur is about twice the panes'.
        -- Noctalia's translucent mode (themes/acid.toml) still lays an 80 %
        -- surface fill over the whole window, with no option for less: the
        -- opacity rule thins it to ~64 % so the glass shows. Lower, and the
        -- text and accent buttons, which the rule fades with it, wash out.
        -- The fill also covers the rim, so the edge lights are set above the
        -- panes' to read through it.
        hg.preset("acid_settings", {
            inherits = "acid_pane",
            blur_strength = 1.0,
            fresnel_strength = 0.35,
            specular_strength = 0.9,
            bevel_strength = 0.4,
            focus_light = 0.5,
            dark = { tint_color = 0xdce6f007, brightness = 1.2, contrast = 1.0, saturation = 1.15 },
        })
        local settings = { class = "^dev\\.noctalia\\.Noctalia$" }
        hl.window_rule({ match = settings, tag = "+hyprglass_enabled" })
        hl.window_rule({ match = settings, tag = "+hyprglass_preset_acid_settings" })
        hl.window_rule({ match = settings, opacity = "0.8 override" })
    end
end
