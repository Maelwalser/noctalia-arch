-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
hl.on("hyprland.start", function()
    -- Black until the session is locked: Noctalia has to run before it can
    -- lock, and its wallpaper and bar would show for a moment first. Set here
    -- and not in the config proper, so a reload never brings it back. The
    -- timer is the way out if hypr-boot-lock never gets to lift it.
    hl.config({ decoration = { screen_shader = os.getenv("HOME") .. "/.config/hypr/boot-veil.frag" } })
    hl.timer(function()
        hl.config({ decoration = { screen_shader = "" } })
    end, { timeout = 15000, type = "oneshot" })
    hl.exec_cmd("noctalia")
    -- ACID//HUD animated desktop layer (no-op with a warning if quickshell is missing).
    if require("dotfiles_theme") == "acid" then
        hl.exec_cmd("$HOME/.local/bin/hud-overlay start")  -- Hyprland's PATH has no ~/.local/bin
    end
    -- Lock the moment Noctalia answers on its socket, and lift the veil once
    -- the lock scene is painted (hypr-boot-lock).
    hl.exec_cmd("$HOME/.local/bin/hypr-boot-lock")
end)

-- ACID//HUD: a monitor the theme has not seen yet gets its lock art, its lock
-- layout and the bar's sets for its scale (a quick no-op for a known one).
-- While the session is locked this waits for the unlock hook (noctalia
-- themes/acid.toml), which also covers the monitors present at startup.
hl.on("monitor.added", function()
    if require("dotfiles_theme") == "acid" then
        hl.exec_cmd("$HOME/.local/bin/hud-build --lock-sync")
    end
end)
