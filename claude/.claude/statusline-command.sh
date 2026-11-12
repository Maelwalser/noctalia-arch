#!/usr/bin/env bash
# Claude Code status line. Follows the dotfiles theme (`dotfiles-theme`):
#   acid     mirrors the acid-hud zsh prompt:  ▲ mael ── ~/dotfiles ── ⎇ main ⚠
#   classic  mirrors the my-darkblood zsh theme: [mael] [main ⚡] [~/dotfiles]
# Uses ANSI slots only, so the colours follow the terminal palette.
#
# Above that line sits the task row, so a session says what it is doing without
# its window title or a scroll through the chat:
#   ● WORKING  Task row: lead with latest prompt ▸ edit statusline-command.sh
# First what the latest prompt asked for, then the step in progress, both from
# statusline-task-hook.sh; last the session name Claude Code passes in
# (/rename, --name or its generated one), which only says what the session
# started out as.

input=$(cat)

user=$(whoami)
cwd=$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input")
actual_dir="$cwd"
cwd="${cwd/#$HOME/\~}"

git_branch=$(git -C "$actual_dir" --no-optional-locks branch --show-current 2>/dev/null)
git_dirty=$(git -C "$actual_dir" --no-optional-locks status --porcelain 2>/dev/null)

theme=$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/theme" 2>/dev/null)
reset=$'\e[0m'

# clip <string> <width>: the string, cut to width with an ellipsis.
clip() {
  if ((${#1} <= $2)); then
    printf '%s' "$1"
  elif (($2 > 1)); then
    printf '%s…' "${1:0:$2-1}"
  fi
}

# task_row <accent> <text> <dim> <warn>: print the task row, or nothing for a
# session with neither a title nor a prompt yet. On a narrow terminal the
# session name goes first, then the step, and then the task is cut short; the
# state marker and the task always stay.
task_row() {
  local accent="$1" text="$2" dim="$3" warn="$4"
  local dir="${XDG_RUNTIME_DIR:-/tmp}/claude-task"
  local sid name state="" task="" activity="" head colour
  IFS=$'\x1f' read -r sid name < <(
    jq -r '[.session_id // "", .session_name // ""] | join("\u001f")' <<<"$input"
  )
  if [[ "$sid" =~ ^[A-Za-z0-9_-]+$ ]]; then
    [[ -r "$dir/$sid.state" ]] && state=$(<"$dir/$sid.state")
    # The label follows its prompt by a few seconds; the prompt stands in.
    if [[ -r "$dir/$sid.label" ]]; then
      task=$(<"$dir/$sid.label")
    elif [[ -r "$dir/$sid.prompt" ]]; then
      task=$(<"$dir/$sid.prompt")
    fi
    [[ -r "$dir/$sid.activity" ]] && activity=$(<"$dir/$sid.activity")
  fi
  # No prompt yet (a resumed session): the name is all there is to say.
  [[ -z "$task" ]] && task="$name" name=""
  [[ -n "$task" ]] || return 0

  case "$state" in
  working) head="● WORKING" colour="$accent" ;;
  waiting) head="● WAITING" colour="$warn" ;;
  "done") head="○ DONE" colour="$dim" ;;
  *) head="○ IDLE" colour="$dim" ;;
  esac

  # The status line cannot ask the terminal for its size; Claude Code passes
  # it in COLUMNS. A few cells are kept back for the row's own padding.
  local budget=$((${COLUMNS:-80} - 4 - ${#head} - 2))
  task=$(clip "$task" 72)
  activity=$(clip "$activity" 32)
  # Cells the segments take: " ▸ " before the step, " ── " before the name.
  width() {
    echo $((${#task} + (${#activity} ? ${#activity} + 3 : 0) + (${#name} ? ${#name} + 4 : 0)))
  }
  (($(width) > budget)) && name=""
  (($(width) > budget)) && activity=""
  task=$(clip "$task" "$budget")
  [[ -n "$task" ]] || return 0

  local row="${colour}${head}${reset}  ${text}${task}${reset}"
  [[ -n "$activity" ]] && row+="${dim} ▸ ${activity}"
  [[ -n "$name" ]] && row+="${dim} ── ${name}"
  echo "${row}${reset}"
}

if [[ "$theme" == classic ]]; then
  red=$'\e[0;31m'
  bold_white=$'\e[1;37m'
  task_row "$red" "$bold_white" $'\e[0;90m' $'\e[0;33m'
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
task_row "$acid" "$bone" "$dim" "$warn"

line="${acid}▲ ${bone}${user}${reset}${dim} ── ${reset}${cwd}"
if [[ -n "$git_branch" ]]; then
  line+="${dim} ── ${acid}⎇ ${reset}${git_branch}"
  [[ -n "$git_dirty" ]] && line+=" ${warn}⚠"
fi
[[ -n "$model" ]] && line+="${dim} ── ${acid}◆ ${dim}${model^^}"
echo "${line}${reset}"
