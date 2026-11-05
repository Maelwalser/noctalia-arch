# ACID//HUD: two-line HUD prompt. Uses ANSI slots only, so it follows the
# Noctalia terminal palette (green = acid accent, bright black = outline grey).
#
#   ┌─▲ mael ── ~/dotfiles ── ⎇ main ⚠ ── ✖ 1
#   └─▶

local acid="%{$fg[green]%}"
local bone="%{$fg_bold[white]%}"
local dim="%F{8}"
local alert="%{$fg_bold[red]%}"
local rst="%{$reset_color%}"

PROMPT="${dim}┌─${acid}▲ ${bone}%n${rst}${dim} ── ${rst}%~${dim}\$(git_prompt_info)%(?,, ${dim}── ${alert}✖ %?)${rst}
${dim}└─${acid}▶${rst} "
PS2="${dim}  ${acid}▸${rst} "

ZSH_THEME_GIT_PROMPT_PREFIX=" ${dim}── ${acid}⎇ ${rst}"
ZSH_THEME_GIT_PROMPT_SUFFIX="${rst}"
ZSH_THEME_GIT_PROMPT_DIRTY=" %{$fg[yellow]%}⚠"
ZSH_THEME_GIT_PROMPT_CLEAN=""
