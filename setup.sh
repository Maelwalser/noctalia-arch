#!/usr/bin/env bash
set -euo pipefail

readonly DOTFILES_ROOT="$(cd "$(dirname "$0")" && pwd)"
readonly TARGET="$HOME"
readonly PACKAGES=(ghostty hyprland neovim obsidian tmux vivaldi zsh)

command -v stow &>/dev/null || { echo "stow not found"; exit 1; }

cd "$DOTFILES_ROOT"

for pkg in "${PACKAGES[@]}"; do
  echo "Stowing $pkg..."
  if ! stow -R -t "$TARGET" "$pkg" 2>&1; then
    echo "  ⚠ $pkg failed — try: stow --adopt -t $TARGET $pkg"
  fi
done

echo "✅ Done"
