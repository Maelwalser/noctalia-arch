#!/usr/bin/env bash

# --- Configuration ---
# An array of all Stow packages to be managed.
readonly PACKAGES=(
    ghostty
    hyprland
    neovim
    obsidian
    tmux
    vivaldi
    zsh
)


# Ensures the script runs from its own directory (the dotfiles root).
cd "$(dirname "$0")" || exit
DOTFILES_ROOT=$(pwd)
echo "Operating from dotfiles root: ${DOTFILES_ROOT}"

# Verify 'stow' is installed before proceeding.
if ! command -v stow &> /dev/null; then
    echo "🔴 Error: 'stow' is not found in your PATH."
    echo "Please install GNU Stow to continue."
    exit 1
fi

# 3. Stow Execution
echo "🚀 Beginning stow operation..."
echo "Packages to stow: ${PACKAGES[*]}"

stow -R "${PACKAGES[@]}"

echo "✅ Stow operation complete."
echo "Review any 'CONFLICT' messages above to resolve pre-existing files."
