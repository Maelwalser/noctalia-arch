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
