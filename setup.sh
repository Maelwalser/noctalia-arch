#!/usr/bin/env bash
set -euo pipefail

readonly DOTFILES_ROOT="$(cd "$(dirname "$0")" && pwd)"
readonly TARGET="$HOME"
readonly PACKAGES=(ghostty gnupg gtk hyprland neovim noctalia obsidian qt6ct sioyek tmux vivaldi zsh)

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
# ignore color-scheme=prefer-dark, so they need a dark theme by name.
# adw-gtk3-dark (pacman: adw-gtk-theme) is what Noctalia's gtk template hook
# sets too; this only covers the time before Noctalia first applies colours.
# Without the package, keep "Adwaita" + the stowed settings.ini prefer-dark
# flag: gtk3 has no "Adwaita-dark" theme and silently falls back to light.
if command -v gsettings &>/dev/null; then
  echo "Setting GTK dark theme..."
  gsettings set org.gnome.desktop.interface color-scheme prefer-dark
  if [[ -d /usr/share/themes/adw-gtk3-dark ]]; then
    gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark
  else
    echo "  ⚠ adw-gtk-theme not installed — GTK apps won't follow the Noctalia palette"
    gsettings set org.gnome.desktop.interface gtk-theme Adwaita
  fi
fi

echo "✅ Done"
