-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
hl.on("hyprland.start", function()
    hl.exec_cmd("noctalia")
    -- ACID//HUD animated desktop layer (no-op with a warning if quickshell is missing).
    if require("dotfiles_theme") == "acid" then
        hl.exec_cmd("hud-overlay start")
    end
    hl.exec_cmd("sleep 1 && noctalia msg session lock")
end)
