#!/usr/bin/env bash
#
# Bring a fresh Arch install up to this desktop. Run as the normal user (it
# calls sudo itself) from a checkout of this repo:
#
#   sudo pacman -S --needed git && git clone <repo> ~/dotfiles && ~/dotfiles/bootstrap.sh
#
# Usage: bootstrap.sh [--profile laptop] [--dev] [--security] [--theme acid|classic]
#                     [--only step[,step...]] [--dry-run]
#
#   --profile laptop   also install the Intel + NVIDIA hybrid laptop's drivers,
#                      module options and kernel command line (system/laptop)
#   --dev              also install the language toolchains and the CLI tools
#                      listed in packages/{cargo,go,uv-tools}.txt
#   --security         also install the security tooling listed in
#                      packages/security*.txt
#   --only             run just these steps: packages system shell dotfiles
#                      claude dev security
#   --dry-run          print what would run, change nothing
#
# Every step is safe to rerun. A failing command warns and the run goes on, so
# one broken package never blocks the rest; the warnings are repeated at the end.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DOTFILES
readonly ALL_STEPS=(packages system shell dotfiles claude dev security)
readonly CLAUDE_CONFIG_REPO="git@github.com:Maelwalser/claude-config.git"
readonly CLAUDE_CONFIG_DIR_LOCAL="$HOME/claude-config"
# The MCC modules installed into ~/.claude (claude-config's install-state).
readonly MCC_MODULES="rules-core,rules-golang,rules-python,rules-typescript,rules-rust,rules-java,rules-dart,rules-web,rules-osdev,agents-core,agents-golang,agents-python,agents-typescript,agents-rust,agents-java,agents-dart,agents-cpp,agents-osdev,skills-golang,skills-python,skills-rust,skills-java,skills-dart,skills-cpp,skills-web,skills-osdev,skills-devops,skills-security,skills-agent-harness,skills-workflow,skills-mcc,skills-llm,scripts-cli,commands-core,commands-golang,commands-python,commands-rust,commands-cpp,commands-java,commands-dart,commands-osdev,hooks-runtime,hooks-osdev,contexts,global-instructions"
readonly CLAUDE_PLUGINS=(gopls-lsp rust-analyzer-lsp clangd-lsp coderabbit)
readonly SERVICES=(bluetooth docker keyd NetworkManager power-profiles-daemon sddm
  systemd-networkd systemd-resolved systemd-timesyncd tailscaled ufw proton.VPN)
readonly LAPTOP_SERVICES=(thermald nvidia-powerd)
readonly GROUPS_WANTED=(wheel audio video kvm uucp docker libvirt)

profile="" dev=0 security=0 dry=0 theme="" only=""
warnings=()

usage() { sed -n '3,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while (( $# )); do
  case "$1" in
    --profile) profile="${2:?--profile needs a name}"; shift 2 ;;
    --profile=*) profile="${1#*=}"; shift ;;
    --theme) theme="${2:?--theme needs acid or classic}"; shift 2 ;;
    --theme=*) theme="${1#*=}"; shift ;;
    --only) only="${2:?--only needs a step list}"; shift 2 ;;
    --only=*) only="${1#*=}"; shift ;;
    --dev) dev=1; shift ;;
    --security) security=1; shift ;;
    --dry-run) dry=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

(( EUID != 0 )) || { echo "Run as your user, not root: the script calls sudo itself." >&2; exit 1; }
[[ -z "$profile" || -d "$DOTFILES/system/$profile" ]] || { echo "unknown profile: $profile" >&2; exit 2; }
for s in ${only//,/ }; do
  [[ " ${ALL_STEPS[*]} " == *" $s "* ]] || { echo "unknown step: $s (steps: ${ALL_STEPS[*]})" >&2; exit 2; }
done

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
warn() { printf '  ⚠ %s\n' "$*" >&2; warnings+=("$*"); }

# run <cmd...>: run it, or print it under --dry-run. A failure only warns.
run() {
  if (( dry )); then
    printf '  +'; printf ' %q' "$@"; printf '\n'
    return 0
  fi
  "$@" || warn "failed: $*"
}

wanted() { [[ -z "$only" ]] && return 0; [[ ",$only," == *",$1,"* ]]; }

# Package names from a list file: one per line, # comments and blanks dropped.
list() { [[ -f "$1" ]] && sed -e 's/[[:space:]]*#.*//' -e '/^[[:space:]]*$/d' "$1"; }

# ── packages ────────────────────────────────────────────────────────
step_packages() {
  say "Packages"
  local -a pkgs aur
  mapfile -t pkgs < <(list "$DOTFILES/packages/pacman.txt"; [[ -z "$profile" ]] || list "$DOTFILES/packages/$profile.txt")
  mapfile -t aur < <(list "$DOTFILES/packages/aur.txt"; [[ -z "$profile" ]] || list "$DOTFILES/packages/$profile-aur.txt")
  # pacman aborts the whole transaction on one unknown name, so a package that
  # was renamed or dropped since the list was written is filtered out first.
  run sudo pacman -Syu --noconfirm
  if (( ! dry )); then
    local p
    local -a known=()
    for p in "${pkgs[@]}"; do
      if pacman -Si "$p" &>/dev/null; then known+=("$p"); else warn "not in the repos, skipped: $p"; fi
    done
    pkgs=("${known[@]}")
  fi
  run sudo pacman -S --needed --noconfirm "${pkgs[@]}"

  if ! command -v yay &>/dev/null; then
    local tmp
    tmp="$(mktemp -d)"
    run git clone --depth 1 https://aur.archlinux.org/yay.git "$tmp/yay"
    (( dry )) || (cd "$tmp/yay" && makepkg -si --noconfirm) || warn "building yay failed"
    rm -rf "$tmp"
  fi
  if command -v yay &>/dev/null || (( dry )); then
    # One at a time: a single failing AUR build must not stop the others.
    local a
    for a in "${aur[@]}"; do run yay -S --needed --noconfirm "$a"; done
  else
    warn "yay missing: AUR packages skipped (${#aur[@]} in packages/aur.txt)"
  fi
}

# ── system ──────────────────────────────────────────────────────────
# install_tree <dir>: copy <dir>/etc/** to /etc/**, root-owned, mode 644.
install_tree() {
  local src="$1" f
  [[ -d "$src/etc" ]] || return 0
  while IFS= read -r -d '' f; do
    run sudo install -Dm644 "$f" "/${f#"$src/"}"
  done < <(find "$src/etc" -type f -print0 | sort -z)
}

step_system() {
  say "System configuration"
  install_tree "$DOTFILES/system"
  [[ -z "$profile" ]] || install_tree "$DOTFILES/system/$profile"

  # SDDM logs straight into Hyprland, whose autostart locks the session at once.
  if (( dry )); then
    echo "  + write /etc/sddm.conf.d/autologin.conf (User=$USER, Session=hyprland)"
  else
    printf '[Autologin]\nUser=%s\nSession=hyprland\n' "$USER" \
      | sudo install -Dm644 /dev/stdin /etc/sddm.conf.d/autologin.conf || warn "could not write the SDDM autologin"
  fi

  # Swiss German keyboard on the console and in X11/SDDM, English messages.
  run sudo sed -i -E 's/^#(en_US\.UTF-8 UTF-8|de_CH\.UTF-8 UTF-8)/\1/' /etc/locale.gen
  run sudo locale-gen
  run sudo localectl set-locale LANG=en_US.UTF-8
  run sudo localectl --no-convert set-keymap sg
  run sudo localectl --no-convert set-x11-keymap ch
  run sudo timedatectl set-timezone Europe/Zurich
  run sudo timedatectl set-ntp true

  # systemd-resolved answers DNS (DoT, no LLMNR: see resolved.conf.d).
  # Started now, not just enabled: the stub file only exists while resolved
  # runs, and the rest of this script still needs DNS.
  run sudo systemctl enable --now systemd-resolved.service
  run sudo ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

  local g
  for g in "${GROUPS_WANTED[@]}"; do
    getent group "$g" &>/dev/null && run sudo usermod -aG "$g" "$USER"
  done
  [[ "$(getent passwd "$USER" | cut -d: -f7)" == /usr/bin/zsh ]] || run sudo chsh -s /usr/bin/zsh "$USER"

  # Enabled, not started: starting SDDM here would take over the screen. The
  # reboot at the end brings everything up.
  local unit
  local -a units=("${SERVICES[@]}")
  [[ "$profile" != laptop ]] || units+=("${LAPTOP_SERVICES[@]}")
  for unit in "${units[@]}"; do
    if systemctl cat "$unit.service" &>/dev/null || (( dry )); then
      run sudo systemctl enable "$unit.service"
    else
      warn "unit $unit.service not installed; not enabled"
    fi
  done

  if command -v ufw &>/dev/null || (( dry )); then
    run sudo ufw default deny incoming
    run sudo ufw default allow outgoing
    run sudo ufw default deny routed
    run sudo ufw logging low
    # Deny-incoming would cut the very session this runs in.
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
      warn "running over SSH: firewall configured but not switched on; run 'sudo ufw enable' locally"
    else
      run sudo ufw --force enable
    fi
  fi
  run sudo sysctl --system

  # system/etc carries a mkinitcpio hook (plymouth) and GRUB defaults (hidden
  # menu, splash), the laptop profile more of both: regenerate on every profile.
  run sudo mkinitcpio -P
  if [[ -f /boot/grub/grub.cfg ]]; then
    run sudo grub-mkconfig -o /boot/grub/grub.cfg
  else
    warn "no /boot/grub/grub.cfg: add the options in system/**/etc/default/grub.d/*.cfg to your bootloader by hand"
  fi
}

# ── shell ───────────────────────────────────────────────────────────
# Must run before the dotfiles step: with no ~/.oh-my-zsh, stow would link that
# whole directory into the repo and the clone below would land inside it.
clone() {
  local repo="$1" dir="$2"
  [[ -d "$dir/.git" ]] || run git clone --depth 1 "$repo" "$dir"
}

step_shell() {
  say "oh-my-zsh and plugins"
  local custom="$HOME/.oh-my-zsh/custom/plugins"
  clone https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
  clone https://github.com/zsh-users/zsh-autosuggestions "$custom/zsh-autosuggestions"
  clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$custom/zsh-syntax-highlighting"
}

# ── dotfiles ────────────────────────────────────────────────────────
step_dotfiles() {
  say "Dotfiles (setup.sh)"
  local -a args=()
  [[ -z "$theme" ]] || args=(--theme "$theme")
  run "$DOTFILES/setup.sh" "${args[@]}"
}

# ── claude ──────────────────────────────────────────────────────────
step_claude() {
  say "Claude Code"
  export PATH="$HOME/.local/bin:$PATH"
  if ! command -v claude &>/dev/null; then
    if (( dry )); then
      echo "  + curl -fsSL https://claude.ai/install.sh | bash"
    else
      curl -fsSL https://claude.ai/install.sh | bash || warn "Claude Code install failed"
    fi
  fi

  # Rules, agents, skills, commands and hooks come from the private
  # claude-config repo (MCC), which needs this machine's SSH key on GitHub.
  if [[ ! -d "$CLAUDE_CONFIG_DIR_LOCAL/.git" ]]; then
    run git clone "$CLAUDE_CONFIG_REPO" "$CLAUDE_CONFIG_DIR_LOCAL"
  fi
  if [[ -f "$CLAUDE_CONFIG_DIR_LOCAL/scripts/mcc.js" ]]; then
    run node "$CLAUDE_CONFIG_DIR_LOCAL/scripts/mcc.js" install --modules "$MCC_MODULES"
  elif (( ! dry )); then
    warn "claude-config not cloned (SSH key on GitHub?): rerun with --only claude"
  fi

  if command -v claude &>/dev/null; then
    local servers p
    servers="$(claude mcp list 2>/dev/null || true)"
    grep -q '^context7' <<<"$servers" \
      || run claude mcp add -s user context7 -- npx -y @upstash/context7-mcp@2.1.4
    grep -q '^playwright' <<<"$servers" \
      || run claude mcp add -s user playwright -- npx -y @playwright/mcp@latest --headless --browser chromium
    for p in "${CLAUDE_PLUGINS[@]}"; do
      run claude plugin install "$p@claude-plugins-official"
    done
  fi
}

# ── dev ─────────────────────────────────────────────────────────────
step_dev() {
  say "Toolchains and CLI tools"
  export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
  local t

  # rustup next to pacman's rust: ~/.cargo/bin is first on PATH (zsh/.zshenv).
  if ! command -v rustup &>/dev/null; then
    if (( dry )); then
      echo "  + curl https://sh.rustup.rs | sh -s -- -y --no-modify-path"
    else
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path \
        || warn "rustup install failed"
    fi
  fi
  if command -v rustup &>/dev/null || (( dry )); then
    run rustup toolchain install stable nightly
    run rustup component add rust-src rust-analyzer clippy rustfmt
  fi
  while IFS= read -r t; do run cargo install --locked "$t"; done < <(list "$DOTFILES/packages/cargo.txt")
  while IFS= read -r t; do run go install "$t"; done < <(list "$DOTFILES/packages/go.txt")
  while IFS= read -r t; do run uv tool install "$t"; done < <(list "$DOTFILES/packages/uv-tools.txt")

  clone_flutter
}

clone_flutter() {
  [[ -d "$HOME/.flutter-sdk/.git" ]] \
    || run git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/.flutter-sdk"
}

# ── security ────────────────────────────────────────────────────────
step_security() {
  say "Security tooling"
  export PATH="$HOME/.local/bin:$PATH"
  local t
  local -a pkgs
  mapfile -t pkgs < <(list "$DOTFILES/packages/security.txt")
  run sudo pacman -S --needed --noconfirm "${pkgs[@]}"
  while IFS= read -r t; do run go install "$t"; done < <(list "$DOTFILES/packages/security-go.txt")
  while IFS= read -r t; do run uv tool install "$t"; done < <(list "$DOTFILES/packages/security-uv.txt")
  while IFS= read -r t; do run pipx install "$t"; done < <(list "$DOTFILES/packages/security-pipx.txt")
}

# ── main ────────────────────────────────────────────────────────────
if (( ! dry )); then
  sudo -v
  # AUR and cargo builds outlast sudo's timestamp; keep it fresh until we exit.
  ( while kill -0 "$$" 2>/dev/null; do sudo -n -v 2>/dev/null || exit; sleep 50; done ) &
fi

for step in "${ALL_STEPS[@]}"; do
  wanted "$step" || continue
  # --dev and --security gate their steps unless those were asked for by name.
  [[ "$step" != dev || $dev -eq 1 || ",$only," == *",dev,"* ]] || continue
  [[ "$step" != security || $security -eq 1 || ",$only," == *",security,"* ]] || continue
  "step_$step"
done

say "Left to do by hand (secrets and licensed files are never in this repo)"
cat <<'EOF'
  • GnuPG key and ~/.password-store   copy from the old machine (pass is not a git repo)
  • ~/.ssh                            copy the keys, or make new ones and add them to GitHub
  • ~/Pictures/ricing                 the licensed HUD art; then run: hud-build && dotfiles-theme acid
  • ~/Pictures/Wallpapers             the classic theme's wallpapers
  • Vivaldi                           sign in to sync; Settings → Appearance → Custom UI
                                      Modifications → ~/dotfiles/vivaldi; load
                                      vivaldi/extensions/shift-copy-image at vivaldi://extensions
  • Obsidian                          open the vaults, then rerun: dotfiles-theme <theme>
  • Logins                            claude, gh auth login, sudo tailscale up, protonvpn
  • monitors                          hyprland/.config/hypr/monitors.lua names this laptop's outputs
EOF

if (( ${#warnings[@]} )); then
  say "Warnings"
  printf '  ⚠ %s\n' "${warnings[@]}"
fi
say "Done. Reboot to start SDDM and Hyprland."
