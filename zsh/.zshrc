ZSH_THEME="my-darkblood"

# ALIAS
alias vim='nvim'
alias lg='lazygit'
alias ld='lazydocker'
alias ka='killall'
alias cl='claude --dangerously-skip-permissions'

export EDITOR='nvim'
export VISUAL='nvim'
export SUDO_EDITOR='nvim'

# Plugins
 plugins=(
  git
  zsh-autosuggestions
  vi-mode
  zsh-syntax-highlighting
  kollzsh
  )

source $ZSH/oh-my-zsh.sh

# Don't exit the shell on Ctrl+D (EOF). Use `exit` to close deliberately.
setopt IGNORE_EOF

# Plugins settings
ZSH_VI_MODE_SET_CURSOR=false
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#6b5d5a,standout"
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE="20"
ZSH_AUTOSUGGEST_USE_ASYNC=1

KOLLZSH_MODEL="qwen2.5-coder:3b"
KOLLZSH_HOTKEY="^o"
KOLLZSH_COMMAND_COUNT=5


export _ZO_DOCTOR=0

# Tools
eval "$(zoxide init zsh --cmd cd)"


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

# opencode
export PATH=/home/mael/.opencode/bin:$PATH


# --- AI AGENT TOOLKIT ---

# (ai) - "AI Agent Launcher"
ai() {
  local VPS_IP="168.119.229.241"
  local LLM_PORT=11434
  local LOCAL_CLIENT_PORT=5005  # We pivot away from the blocked port 5000
  local REMOTE_SERVER_PORT=5000
  local KEY_PATH="$HOME/.ssh/id_ed25519"
  local LOCAL_ENV="$HOME/llm_env"
  local SOCKET="/tmp/ssh-ai-tunnel.sock"

  # --- CLEANUP ---
  rm -f "$SOCKET"
  pkill -f "L ${LLM_PORT}:localhost" 2>/dev/null
  pkill -f "L ${LOCAL_CLIENT_PORT}:localhost" 2>/dev/null
  # Force kill anything currently sitting on 5005 just in case
  fuser -k ${LOCAL_CLIENT_PORT}/tcp 2>/dev/null 

  echo "📡 Tunnels: Local 5005 -> VPS 5000 | Local 11434 -> VPS 11434"

  # --- START TUNNEL ---
  # Mapping: -L [Local Port]:[Remote Host]:[Remote Port]
  ssh -f -N -M -S "$SOCKET" \
      -L ${LLM_PORT}:localhost:${LLM_PORT} \
      -L ${LOCAL_CLIENT_PORT}:localhost:${REMOTE_SERVER_PORT} \
      -i "${KEY_PATH}" \
      -o ExitOnForwardFailure=yes \
      llm_admin@${VPS_IP}

  if [ $? -ne 0 ]; then
    echo "❌ Tunnel failed. Try changing LOCAL_CLIENT_PORT to 5006."
    return 1
  fi

  trap "ssh -S '$SOCKET' -O exit llm_admin@${VPS_IP} 2>/dev/null; rm -f '$SOCKET'; return" EXIT SIGINT

  echo "🤖 Launching Local CLI..."
  (
    source "${LOCAL_ENV}/bin/activate"
    # Ensure your local script points to http://localhost:5005
    python3 "${LOCAL_ENV}/ai_client.py"
  )
}

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
