-- --- Hybrid GPU (Intel Iris Xe + Nvidia RTX 3050 Mobile) ---
-- The ultrawide (DP-4) is driven by the Intel iGPU and the dGPU drives no
-- display, so no explicit GPU environment is needed here.

hl.env("XDG_SESSION_TYPE", "wayland")

-- Qt apps read their palette from qt6ct / qt5ct, which Noctalia's qt template
-- feeds. The name is qt5ct for both: Qt5 apps (sioyek) only know that plugin,
-- and qt6ct answers to it as well, while "qt6ct" leaves Qt5 apps unthemed.
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")

-- One cursor size for everything. Unset, XWayland apps (sioyek's AppImage has
-- no Wayland plugin) derive theirs from the X screen's dimensions, so it grows
-- with every monitor attached, and Hyprland then multiplies that by the
-- monitor scale. Both names: Hyprland reads HYPRCURSOR_SIZE, X apps XCURSOR_SIZE.
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
