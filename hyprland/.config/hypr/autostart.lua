-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
hl.on("hyprland.start", function()
    hl.exec_cmd("noctalia")
    -- ACID//HUD animated desktop layer (no-op with a warning if quickshell is missing).
    if require("dotfiles_theme") == "acid" then
        hl.exec_cmd("$HOME/.local/bin/hud-overlay start")  -- Hyprland's PATH has no ~/.local/bin
    end
    hl.exec_cmd("sleep 1 && noctalia msg session lock")
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
