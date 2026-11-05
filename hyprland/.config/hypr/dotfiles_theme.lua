-- Active dotfiles theme, "acid" (ACID//HUD) or "classic", as chosen with
-- `dotfiles-theme <name>`, which also runs `hyprctl reload`. Defaults to acid
-- when nothing has been chosen yet.
local state = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
local f = io.open(state .. "/dotfiles/theme", "r")
local name = f and f:read("*l")
if f then
    f:close()
end
return name == "classic" and "classic" or "acid"
