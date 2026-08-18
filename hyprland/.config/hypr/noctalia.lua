-- noctalia-shell writes its palette to a hyprlang `.conf` file, which the Lua
-- config cannot `source`. Parse the `$var = ...` definitions out of that file
-- and apply the same mapping its template does. If the file is missing or its
-- variable names change, keep Hyprland's defaults instead of erroring out.
--
-- noctalia runs `hyprctl reload` after rewriting the file, so theme switches
-- still apply live.

local COLORS_PATH = os.getenv("HOME") .. "/.config/hypr/noctalia/noctalia-colors.conf"

local function read_palette(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end

    local palette = {}
    for line in file:lines() do
        local name, value = line:match("^%s*%$([%w_]+)%s*=%s*(.-)%s*$")
        if name then
            palette[name] = value
        end
    end
    file:close()

    return palette
end

local palette = read_palette(COLORS_PATH)
if not palette or not palette.primary then
    return
end

hl.config({
    general = {
        col = {
            active_border = palette.primary,
            inactive_border = palette.surface,
        },
    },

    group = {
        col = {
            border_active = palette.secondary,
            border_inactive = palette.surface,
            border_locked_active = palette.error,
            border_locked_inactive = palette.surface,
        },

        groupbar = {
            col = {
                active = palette.secondary,
                inactive = palette.surface,
                locked_active = palette.error,
                locked_inactive = palette.surface,
            },
        },
    },
})
