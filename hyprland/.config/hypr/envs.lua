-- --- Hybrid GPU (Intel Iris Xe + Nvidia RTX 3050 Mobile) ---
-- The ultrawide (DP-4) is driven by the Intel iGPU and the dGPU drives no
-- display, so no explicit GPU environment is needed here.

hl.env("XDG_SESSION_TYPE", "wayland")
