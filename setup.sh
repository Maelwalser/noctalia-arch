#!/usr/bin/env bash
set -euo pipefail

readonly DOTFILES_ROOT="$(cd "$(dirname "$0")" && pwd)"
readonly TARGET="$HOME"
readonly PACKAGES=(btop claude fastfetch ghostty gnupg gtk hud hyprland neovim noctalia obsidian qt6ct quickshell sioyek theme tmux vivaldi zsh)

# Desktop theme: acid (ACID//HUD) or classic. Defaults to the one already
# chosen on this machine, else acid. Switch later with `dotfiles-theme <name>`.
theme="$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/theme" 2>/dev/null || echo acid)"
while (( $# )); do
  case "$1" in
    --theme) theme="${2:?--theme needs acid or classic}"; shift 2 ;;
    --theme=*) theme="${1#--theme=}"; shift ;;
    *) echo "usage: $0 [--theme acid|classic]"; exit 2 ;;
  esac
done
[[ "$theme" == acid || "$theme" == classic ]] || { echo "unknown theme: $theme"; exit 2; }

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

# ── Hyprland plugins ────────────────────────────────────────────────
# Built from pinned commits (hyprpm is not in Arch's hyprland package). Rerun
# `hypr-plugins` after every Hyprland update: plugins are version-locked.
if command -v cmake &>/dev/null && pkg-config --exists hyprland 2>/dev/null; then
  echo "Building Hyprland plugins..."
  "$HOME/.local/bin/hypr-plugins" || echo "  ⚠ hypr-plugins failed — rerun it to see the error"
else
  echo "  ⚠ cmake or Hyprland headers missing — skipped hypr-plugins"
fi

# ── ACID//HUD theme ─────────────────────────────────────────────────
# hud-build crops the UI elements out of the vector packs in ~/Pictures/ricing
# (licensed stock art, never committed) and renders wallpapers, bar frames,
# lockscreen stickers and overlay layers into ~/.local/share/hud.
hud_missing=()
for tool in gs pdftocairo magick qs; do
  command -v "$tool" &>/dev/null || hud_missing+=("$tool")
done
if (( ${#hud_missing[@]} )); then
  echo "  ⚠ ACID//HUD needs: ${hud_missing[*]} — pacman -S ghostscript poppler imagemagick quickshell"
fi
if [[ -d "$HOME/Pictures/ricing" ]] && command -v gs &>/dev/null && command -v magick &>/dev/null; then
  echo "Building ACID//HUD assets..."
  "$HOME/.local/bin/hud-build" || echo "  ⚠ hud-build failed — rerun it to see the error"
else
  echo "  ⚠ ~/Pictures/ricing or build tools missing — skipped hud-build"
fi
if pgrep -x noctalia &>/dev/null; then
  # The bar ornaments plugin lives in this repo; register its folder once.
  # Output is captured first: `grep -q` exiting early would SIGPIPE the
  # producer and, under pipefail, look like "not registered".
  sources="$(noctalia msg plugins source list 2>/dev/null || true)"
  if ! grep -q '^hud ' <<<"$sources"; then
    noctalia msg plugins source add hud path "$HOME/.local/share/hud-src/noctalia-plugins" \
      || echo "  ⚠ could not register the hud plugin source"
  fi
fi

# ── Theme ───────────────────────────────────────────────────────────
# Links each app's theme variant, swaps Noctalia's palette/wallpaper/lockscreen
# state, starts or stops the HUD overlay and reloads what is running.
echo "Applying theme $theme..."
"$HOME/.local/bin/dotfiles-theme" "$theme" || echo "  ⚠ dotfiles-theme failed — rerun: dotfiles-theme $theme"

echo "✅ Done"
