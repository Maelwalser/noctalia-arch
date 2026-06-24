#!/usr/bin/env bash
set -euo pipefail

readonly DOTFILES_ROOT="$(cd "$(dirname "$0")" && pwd)"
readonly TARGET="$HOME"
readonly PACKAGES=(ghostty hyprland neovim obsidian sioyek tmux vivaldi zsh)

command -v stow &>/dev/null || { echo "stow not found"; exit 1; }

cd "$DOTFILES_ROOT"

for pkg in "${PACKAGES[@]}"; do
  echo "Stowing $pkg..."
  if ! stow -R -t "$TARGET" "$pkg" 2>&1; then
    echo "  ⚠ $pkg failed — try: stow --adopt -t $TARGET $pkg"
  fi
done

# ── Vivaldi VimFields UI mod ────────────────────────────────────────
# Not stow-managed: it installs into Vivaldi's resources dir (/opt/...) and
# patches window.html, which needs root. Re-run after every Vivaldi update —
# updates overwrite window.html and drop the injected <script>.
if [[ -d /opt/vivaldi ]] || command -v vivaldi &>/dev/null; then
  echo "Installing Vivaldi VimFields mod (needs sudo)..."
  if ! sudo bash "$DOTFILES_ROOT/vivaldi/install.sh"; then
    echo "  ⚠ Vivaldi mod failed — run manually: sudo bash vivaldi/install.sh"
  fi
fi

echo "✅ Done"
