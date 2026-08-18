# .zshenv is sourced by EVERY zsh — interactive shells, scripts, subshells,
# `zsh -c`. Two rules follow from that: keep it free of external commands, and
# make it idempotent. Anything expensive or repeated here is paid many times per
# session, often in places you never see.

# Without this, each nested shell re-prepends the entries below: a nested
# interactive shell reached 44 PATH entries for 17 real directories, slowing
# every command lookup. -U keeps the first occurrence, so precedence is stable.
typeset -U path PATH

export VOLTA_HOME="$HOME/.volta"
export CARGO_HOME="$HOME/.cargo"
export ZSH="$HOME/.oh-my-zsh"

# Hardcoded rather than `$(go env GOPATH)`, which forked a go process on every
# zsh startup — scripts included — to print a value that is just the default.
export GOPATH="$HOME/go"

# Order matters: this reproduces the precedence the old sequence of prepends and
# appends produced. Front of PATH wins.
path=(
  "$HOME/.npm-global/bin"
  "$HOME/.flutter-sdk/bin"
  "$CARGO_HOME/bin"
  "$VOLTA_HOME/bin"
  $path
  "$GOPATH/bin"
)

# GEMINI_API_KEY is NOT set here on purpose. `pass show` costs ~175 ms and spawns
# gpg/keyboxd; doing that per zsh process made it the single largest startup cost
# and let concurrent callers leave stale keyboxd dotlocks that broke gpg after a
# reboot. It is loaded on demand in .zshrc — see load-gemini-key there.

export CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000
export GOPROXY=https://proxy.golang.org,direct
export CHROME_EXECUTABLE=/usr/bin/vivaldi
