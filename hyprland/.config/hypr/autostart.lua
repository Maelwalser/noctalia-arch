-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
hl.on("hyprland.start", function()
    hl.exec_cmd("qs -c noctalia-shell")
    hl.exec_cmd("sleep 1 && qs -c noctalia-shell ipc call lockScreen lock")
end)
