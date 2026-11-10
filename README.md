# dotfiles

Arch Linux + Hyprland + Noctalia desktop, managed with GNU stow.

## New machine

After a base Arch install (user in `wheel`, network up):

```bash
sudo pacman -S --needed git
git clone https://github.com/Maelwalser/noctalia-arch.git ~/dotfiles
~/dotfiles/bootstrap.sh --profile laptop --dev --security   # all flags are optional
```

`bootstrap.sh` runs these steps in order; each is safe to rerun, and
`--only step,step` runs a subset. `--dry-run` prints the commands instead.

| Step | What it does |
|------|--------------|
| `packages` | installs `packages/pacman.txt`, builds yay, installs `packages/aur.txt` |
| `system` | copies `system/etc` to `/etc`, SDDM autologin, locale/keymap/timezone, groups, zsh as login shell, enables services, ufw defaults |
| `shell` | oh-my-zsh and its two plugins |
| `dotfiles` | `setup.sh`: stow, seed files, Vivaldi mod, GTK settings, Hyprland plugins, HUD assets, theme |
| `claude` | Claude Code, the private `claude-config` repo (rules, agents, skills, hooks), MCP servers, plugins |
| `dev` (`--dev`) | rustup, Flutter SDK, and the tools in `packages/{cargo,go,uv-tools}.txt` |
| `security` (`--security`) | the security tooling in `packages/security*.txt` (pacman, go, uv, pipx) |

`--profile laptop` adds `packages/laptop*.txt` and `system/laptop/etc`: the
Intel + NVIDIA hybrid drivers, module options, early KMS and kernel command line.

The script ends with the list of things it cannot do: secrets (GnuPG, `pass`,
SSH keys), the licensed HUD art in `~/Pictures/ricing`, browser and vault sign-ins.

## Layout

- `<package>/` — stow packages, linked into `$HOME` by `setup.sh` (the list is at its top).
- `seed/` — files copied once instead of linked, because their owners rewrite them in place.
- `system/etc/` — system configuration, copied to `/etc`; `system/<profile>/etc/` is hardware specific.
- `packages/` — package lists, one name per line.

## Keeping it current

```bash
./setup.sh                 # after adding a package directory or pulling
dotfiles-theme acid        # or classic
pacman -Qqen               # compare with packages/pacman.txt + laptop.txt
pacman -Qqem               # compare with packages/aur.txt + laptop-aur.txt
```
