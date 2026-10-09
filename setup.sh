#!/usr/bin/env bash
set -euo pipefail

readonly DOTFILES_ROOT="$(cd "$(dirname "$0")" && pwd)"
readonly TARGET="$HOME"
readonly PACKAGES=(ghostty gnupg gtk hyprland neovim noctalia obsidian sioyek tmux vivaldi zsh)

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

# ── GnuPG stale-lock cleanup unit ───────────────────────────────────
# Stowed above; still needs enabling in the systemd user manager.
if command -v systemctl &>/dev/null; then
  echo "Enabling gnupg-clear-stale-locks.service..."
  systemctl --user daemon-reload
  systemctl --user enable gnupg-clear-stale-locks.service
fi

# ── GTK3 dark theme ─────────────────────────────────────────────────
# GTK3 apps (incl. the xdg-desktop-portal-gtk file chooser browsers open)
# ignore color-scheme=prefer-dark and only go dark via the stowed
# gtk-3.0/settings.ini prefer-dark flag. The theme must stay "Adwaita":
# gtk3 has no "Adwaita-dark" theme and silently falls back to light.
if command -v gsettings &>/dev/null; then
  echo "Setting GTK dark theme..."
  gsettings set org.gnome.desktop.interface color-scheme prefer-dark
  gsettings set org.gnome.desktop.interface gtk-theme Adwaita
fi

echo "✅ Done"
