#!/usr/bin/env bash
# Claude Code status line. Follows the dotfiles theme (`dotfiles-theme`):
#   acid     mirrors the acid-hud zsh prompt:  ▲ mael ── ~/dotfiles ── ⎇ main ⚠
#   classic  mirrors the my-darkblood zsh theme: [mael] [main ⚡] [~/dotfiles]
# Uses ANSI slots only, so the colours follow the terminal palette.

input=$(cat)

user=$(whoami)
cwd=$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input")
actual_dir="$cwd"
cwd="${cwd/#$HOME/\~}"

git_branch=$(git -C "$actual_dir" --no-optional-locks branch --show-current 2>/dev/null)
git_dirty=$(git -C "$actual_dir" --no-optional-locks status --porcelain 2>/dev/null)

theme=$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/theme" 2>/dev/null)
reset=$'\e[0m'

if [[ "$theme" == classic ]]; then
  red=$'\e[0;31m'
  bold_white=$'\e[1;37m'
  git_segment=""
  if [[ -n "$git_branch" ]]; then
    if [[ -n "$git_dirty" ]]; then
      git_segment="${red}[${bold_white}${git_branch} ${red}⚡${red}]${reset} "
    else
      git_segment="${red}[${bold_white}${git_branch}${red}]${reset} "
    fi
  fi
  echo "${red}[${bold_white}${user}${red}]${reset} ${git_segment}${red}[${bold_white}${cwd}${red}]${reset}"
  exit 0
fi

acid=$'\e[0;32m'
bone=$'\e[1;37m'
dim=$'\e[0;90m'
warn=$'\e[0;33m'
model=$(jq -r '.model.display_name // empty' <<<"$input")

line="${acid}▲ ${bone}${user}${reset}${dim} ── ${reset}${cwd}"
if [[ -n "$git_branch" ]]; then
  line+="${dim} ── ${acid}⎇ ${reset}${git_branch}"
  [[ -n "$git_dirty" ]] && line+=" ${warn}⚠"
fi
[[ -n "$model" ]] && line+="${dim} ── ${acid}◆ ${dim}${model^^}"
echo "${line}${reset}"
