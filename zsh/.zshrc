# Prompt follows the dotfiles theme (`dotfiles-theme acid|classic`).
_dotfiles_theme="$(<"${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/theme" 2>/dev/null)"
if [[ "$_dotfiles_theme" == classic ]]; then
  ZSH_THEME="my-darkblood"
else
  ZSH_THEME="acid-hud"
fi

# ALIAS
alias vim='nvim'
alias lg='lazygit'
alias ld='lazydocker'
alias ka='killall'
alias c='claude'
alias cr='claude --resume'
alias cl='claude --dangerously-skip-permissions'
# Claude Code draws the ACID//HUD logo instead of its mascot (claude-logo in
# claude/.local/bin). The installer swaps the binary on every update, so the
# patch is applied again, when missing, before each launch.
claude() {
  claude-logo --quiet
  command claude "$@"
}
# Under ACID//HUD eza is themed by ~/.config/eza/theme.yml (linked by
# dotfiles-theme). oh-my-zsh's LS_COLORS would override that file's file kinds
# and extension colours, so eza runs without it; ls and completion keep it.
[[ "$_dotfiles_theme" == classic ]] || alias eza='LS_COLORS= eza'

export EDITOR='nvim'
export VISUAL='nvim'
export SUDO_EDITOR='nvim'

# Secrets from `pass`, loaded on demand. `pass show` costs ~175 ms because it
# spawns gpg and round-trips through keyboxd, so running it at every prompt made
# it two thirds of shell startup. Nothing needs the key until an AI tool asks
# for it, so it is fetched at first use and then inherited by child processes.
load-gemini-key() {
  [[ -n "$GEMINI_API_KEY" ]] && return 0
  export GEMINI_API_KEY="$(pass show gemini/api_key 2>/dev/null)"
  [[ -n "$GEMINI_API_KEY" ]]
}

# nvim plugins read GEMINI_API_KEY from the environment, so populate it just
# before the editor starts. Keeps the old behaviour without the startup cost.
nvim() {
  load-gemini-key
  command nvim "$@"
}

# Picks oh-my-zsh's `compinit -u` branch over `compinit -i`. Note this does NOT
# skip the compaudit world-writable-fpath scan, as previously assumed: compinit
# runs compaudit for both -i and -u, and only -C suppresses it. See the compinit
# wrapper below for the part that actually removes that cost.
ZSH_DISABLE_COMPFIX=true

# oh-my-zsh's auto-update check forks `git --version` and `git rev-parse` on
# every single shell. Updates here are done by hand via `omz update`.
zstyle ':omz:update' mode disabled

# compaudit walks every fpath entry stat'ing for group/world-writable dirs
# (~13 ms), and compinit separately re-scans fpath for completions the dump
# doesn't have yet. Neither needs to happen on every shell: trust the cached
# dump, and force one full rebuild a day so newly installed tools still get
# their completions.
compinit() {
  unfunction compinit
  autoload -Uz compinit
  local dump=${ZSH_COMPDUMP:-${ZDOTDIR:-$HOME}/.zcompdump}
  local -a stale=( ${dump}(Nmh+24) )
  if [[ ! -s $dump ]] || (( $#stale )); then
    compinit "$@"      # full scan
    # compinit only rewrites the dump when its contents changed, so on an
    # unchanged scan the mtime would stay stale and every later shell would
    # redo the full scan. Bump it explicitly to restart the 24 h clock.
    [[ -s $dump ]] && touch "$dump"
  else
    compinit -C "$@"   # cached dump is fresh enough
  fi
}

# Plugins
#
# The `git` plugin is deliberately absent: it costs ~11 ms per shell to define
# ~150 aliases, and across 12k lines of history exactly one of them was ever
# used. The prompt is unaffected — `git_prompt_info` comes from oh-my-zsh's
# lib/git.zsh, which loads regardless of this list. `_git` completion comes
# from zsh itself, not from the plugin.
 plugins=(
  zsh-autosuggestions
  vi-mode
  zsh-syntax-highlighting
  )

source $ZSH/oh-my-zsh.sh

# ls is eza. This has to come after oh-my-zsh, which sets ls='ls --color=tty';
# its l/la/ll/lsa aliases expand through this one. `command ls` is still GNU ls.
(( $+commands[eza] )) && alias ls='eza --icons=auto'

# Don't exit the shell on Ctrl+D (EOF). Use `exit` to close deliberately.
setopt IGNORE_EOF

# Plugins settings
ZSH_VI_MODE_SET_CURSOR=false
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#6b5d5a,standout"
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE="20"
ZSH_AUTOSUGGEST_USE_ASYNC=1


export _ZO_DOCTOR=0

# Tools
# `zoxide init` prints the same script every time, so run it only when zoxide
# itself is newer than the cache rather than forking it on every startup.
() {
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zoxide-init.zsh"
  if [[ ! -s $cache || $commands[zoxide] -nt $cache ]]; then
    mkdir -p "${cache:h}"
    zoxide init zsh --cmd cd >| "$cache"
  fi
  source "$cache"
}


# --- TMUX TOOLKIT ---

# (tma) - "Tmux Main Attach"
# Attaches to a session named "main", or creates it if it doesn't exist.
tma() {
  # Don't run if already inside tmux
  if [[ -n "$TMUX" ]]; then
    echo "Already inside tmux."
    return 1
  fi
  
  # Attach to session 'main' or create it
  tmux attach-session -t main || tmux new-session -s main
}

# (tn) - "Tmux New [name]"
# Creates a new, named session for a specific project.
tn() {
  if [[ -n "$TMUX" ]]; then
    echo "Already inside tmux. Detach first with 'Ctrl+space, d'."
    return 1
  fi

  # Check if a name was provided
  if [[ -z "$1" ]]; then
    echo "Usage: tn <session-name>"
    return 1
  fi

  tmux new-session -s "$1"
}

# (tl) - "Tmux List & Attach"
# Lists all sessions and provides an interactive fzf-based menu to attach.
tl() {
  if [[ -n "$TMUX" ]]; then
    echo "Already inside tmux."
    return 1
  fi

  local session
  session=$(tmux ls -F '#S' | fzf --reverse --prompt="❌ Select Tmux Session > ")
  
  if [[ -n "$session" ]]; then
    tmux attach-session -t "$session"
  fi
}

# (tk) - "Tmux Kill"
# Lists sessions and interactively prompts to kill one.
tk() {
  if [[ -n "$TMUX" ]]; then
    echo "Cannot kill sessions from inside tmux. Detach first."
    return 1
  fi

  local session
  session=$(tmux ls -F '#S' | fzf --reverse --prompt="💀 KILL > ")

  if [[ -n "$session" ]]; then
    echo -n "💀 KILL $session? [y/N] "
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      tmux kill-session -t "$session"
      echo "$session KILLED ⚰️"
    else
      echo "KILL aborted ᶻ 𝗓 𐰁"
    fi
  fi
}

# --- Nice to have ---
# Weather function
weather() {
  curl wttr.in/bern
}

# --- Keybinds ---

# vi-mode
# Unbinding uneeded binds
bindkey -r -M viins '^J' # Enter/LF (accept-line)
bindkey -r -M viins '^A' # beginning-of-line
bindkey -r -M viins '^B' # self-insert
bindkey -r -M viins '^C' # self-insert
bindkey -r -M viins '^D' # list-choices
bindkey -r -M viins '^E' # end-of-line
bindkey -r -M viins '^F' # self-insert
bindkey -r -M viins '^G' # list-expand
bindkey -r -M viins '^H' # backward-delete-char (we rely on ^?)
bindkey -r -M viins '^K' # self-insert
bindkey -r -M viins '^N' # down-history
bindkey -r -M viins '^O' # self-insert
bindkey -r -M viins '^P' # up-history
bindkey -r -M viins '^Q' # vi-quoted-insert
bindkey -r -M viins '^R' # history-incremental-search-backward
bindkey -r -M viins '^S' # history-incremental-search-forward
bindkey -r -M viins '^T' # self-insert
bindkey -r -M viins '^U' # vi-kill-line (your example)
bindkey -r -M viins '^V' # vi-quoted-insert
bindkey -r -M viins '^W' # backward-kill-word
bindkey -r -M viins '^Y' # self-insert
bindkey -r -M viins '^Z' # self-insert

# Unbind complex ^X chord bindings
bindkey -r -M viins '^X^R'
bindkey -r -M viins '^X?'
bindkey -r -M viins '^XC'
bindkey -r -M viins '^Xa'
bindkey -r -M viins '^Xc'
bindkey -r -M viins '^Xd'
bindkey -r -M viins '^Xe'
bindkey -r -M viins '^Xh'
bindkey -r -M viins '^Xm'
bindkey -r -M viins '^Xn'
bindkey -r -M viins '^Xt'
bindkey -r -M viins '^X~'

# Escape is the ONLY key that enters normal (vicmd) mode
bindkey -M viins '^[' vi-cmd-mode

# Ghostty uses the Kitty keyboard protocol: Ctrl+<letter> arrives as "^[[<codepoint>;5u".
# Without explicit bindings, zsh sees the leading ^[ and jumps to vicmd before the rest arrives.
# Map every Ctrl+letter CSI u sequence to a no-op in both modes, then re-bind the two we care about.
for _code in 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122; do
  bindkey -M viins "^[[${_code};5u" undefined-key
  bindkey -M vicmd "^[[${_code};5u" undefined-key
done
unset _code
# Ctrl+I (code 105) → tab completion
bindkey -M viins '^[[105;5u' expand-or-complete
# Ctrl+M (code 109) → accept-line (run the command)
bindkey -M viins '^[[109;5u' accept-line
bindkey -M vicmd '^[[109;5u' accept-line

# Plain Tab / Enter bytes (when kitty protocol isn't active)
bindkey -M viins '^I' expand-or-complete
bindkey -M vicmd '^M' accept-line

# In vicmd, strip all Ctrl-key combos so nothing switches back to insert mode.
for _ctrl_key in '^A' '^B' '^C' '^D' '^E' '^F' '^G' '^H' '^J' '^K' '^L' '^N' '^O' '^P' '^Q' '^R' '^S' '^T' '^U' '^V' '^W' '^X' '^Y' '^Z'; do
  bindkey -r -M vicmd "$_ctrl_key"
done
unset _ctrl_key

# Give zsh 50ms to read multi-byte escape sequences (CSI u, arrow keys)
# before deciding a lone ^[ means "enter vicmd".
KEYTIMEOUT=5



export PATH="$HOME/.local/bin:$PATH"

export PATH="$PATH":"$HOME/.pub-cache/bin"

# The android-sdk-cmdline-tools-latest package ships
# /etc/profile.d/android-sdk-cmdline-tools-latest.sh, which points these at
# /opt/android-sdk — that tree only holds cmdline-tools, so Flutter reports
# "No Android SDK found". The real SDK (platforms, ndk, build-tools) is here.
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"


# (wt) - "Git Worktree Add"
# Atomically creates a new branch and a sibling git worktree.
wt() {
  # 1. Validate input parameters
  if [[ -z "$1" ]]; then
    echo "Usage: wt <branch-name>"
    return 1
  fi

  local wt_name="$1"
  # 2. Define the path as a sibling directory to avoid nesting repositories
  local wt_path="../$wt_name" 

  # 3. Verify execution environment
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: Current directory is not part of a Git repository."
    return 1
  fi

  # 4. Execute atomic creation
  echo "Provisioning branch and worktree: '$wt_name'..."
  git worktree add -b "$wt_name" "$wt_path"
  
  # 5. Output result and navigate
  if [[ $? -eq 0 ]]; then
    echo "✅ Worktree initialized successfully."
    cd "$wt_path"
  else
    echo "❌ Worktree creation failed. Verify that the branch name does not already exist."
  fi
}

# Fastfetch splash. The layout is picked from the live width, and the splash
# is redrawn on every resize until the first command runs: a terminal that is
# tiled after opening (or opens before Hyprland has sized it) would otherwise
# keep a layout chosen for the wrong width and wrap its lines into the logo.
if [[ -o interactive ]] && [[ -z "$TMUX" ]] && (( SHLVL == 1 )); then
  _ff_render() {
    local dir="$HOME/.config/fastfetch" cols=${COLUMNS:-80} rows=${LINES:-24}
    local -a cmd
    # Widths: the ACID emblem takes 28 columns, the classic text logo 69, and
    # the longest line of text (the CPU name) 45, so the logo moves on top as
    # soon as both no longer fit side by side, shrinks to a badge when the
    # window is too short for it, and the module list shrinks under 48
    # columns. In the top layout fastfetch only moves one line past an image,
    # and Ghostty leaves the cursor on its last row, so the right padding, unused
    # there, is the one blank line between the emblem and the text.
    if [[ "$_dotfiles_theme" == classic ]]; then
      if (( cols >= 116 && rows >= 22 )); then
        cmd=(fastfetch)
      elif (( cols >= 72 && rows >= 40 )); then
        cmd=(fastfetch --logo-position top --logo-padding-left 0)
      elif (( cols >= 48 && rows >= 22 )); then
        cmd=(fastfetch -c "$dir/config-compact.jsonc")
      else
        cmd=(fastfetch -c "$dir/config-mini.jsonc")
      fi
    elif (( cols >= 76 && rows >= 22 )); then
      cmd=(fastfetch -c "$dir/config-acid.jsonc")
    elif (( cols >= 48 && rows >= 36 )); then
      cmd=(fastfetch -c "$dir/config-acid.jsonc" --logo-position top --logo-padding-left 0 --logo-padding-right 1)
    elif (( cols >= 48 && rows >= 28 )); then
      cmd=(fastfetch -c "$dir/config-acid.jsonc" --logo-position top --logo-padding-left 0 --logo-padding-top 0 --logo-width 10 --logo-height 4 --logo-padding-right 1)
    elif (( cols >= 48 && rows >= 22 )); then
      cmd=(fastfetch -c "$dir/config-acid.jsonc" --logo-type none)
    else
      cmd=(fastfetch -c "$dir/config-acid-mini.jsonc")
    fi
    # Drop the previous splash, kitty-graphics logo and scrollback included.
    print -n -- $'\e_Ga=d,d=A\e\\\e[H\e[2J\e[3J'
    "${cmd[@]}"
  }
  _ff_render
  TRAPWINCH() {
    zle -I 2>/dev/null  # whatever is being typed is redrawn after the splash
    _ff_render
  }
  _ff_stop() {
    unfunction TRAPWINCH _ff_render _ff_stop
    add-zsh-hook -d preexec _ff_stop
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook preexec _ff_stop
fi
