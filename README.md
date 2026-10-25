# dotfiles

Everything that makes up my Arch + Hyprland + Caelestia desktop, and one script that puts it on a new machine:
the apps, the patched Caelestia shell with the top bar, the rice bar, Hyprland settings and keybinds, the
wallpapers and look, and all the little systems (power modes, eco mode, smart charging, the news brief, the update
check, the Bluetooth agent, the fingerprint and sleep fixes, the screensaver, `/chats` for Claude Code…).

## New machine

Start from a fresh Arch install with Hyprland (archinstall's Hyprland profile is fine). Then, as yourself:

```sh
sudo pacman -S --needed git github-cli
gh auth login                                   # this repo is private
gh repo clone Mr-Pythoneer/dotfiles ~/.local/src/dotfiles
~/.local/src/dotfiles/install.sh
```

It asks for your password once and takes 30–60 minutes, mostly downloads and three builds. Then reboot. At the end
it lists anything that didn't work, and the few things only you can do: sign in to apps, `fprintd-enroll`,
`claude`, and pairing Syncthing again.

`install.sh --files-only` copies just the configs and scripts: no packages and no password.

It's safe to run again. Any file it replaces is kept in `~/.local/state/dotfiles-backup/<date>/`, and a full log is
in `~/.cache/dotfiles-install/`.

## Keeping it up to date (on this laptop)

```sh
~/.local/src/dotfiles/sync.sh --push
```

This copies the current setup in, refreshes the package lists, stops if anything looks like a password or token,
then commits and pushes. Without `--push` it only refreshes the folder, so you can look first.

## What install.sh does

1. **pacman:** turns on colour and holds `caelestia-cli` at the version the top bar was tested with.
2. **Packages:** updates the system, then installs everything in `packages/pacman.txt`. Anything no longer in
   Arch's repos is skipped and listed.
3. **AUR:** installs yay, then everything in `packages/aur.txt`: Chrome, Zen, VS Code, Vesktop, hyprbars, and the
   rest.
4. **Caelestia stack:** builds and installs the exact pinned versions, replacing the official Caelestia or
   Quickshell if the machine came with them:
   - `caelestia-cli` 1.1.3 (`packages/pinned/`)
   - `quickshell-pinned`, with the monitor-unplug fix
   - `caelestia-shell-topbar`
   The last two are in `home/.local/share/arch-kit/pkg/`.
5. **Flatpaks:** Steam.
6. **Files:** copies `home/` into your home. If your user name isn't `mrpythoneer`, it rewrites the paths inside the
   files.
7. **System:** installs these and skips the ones the hardware can't use:
   - `power-tweaks-install`, `eco-mode-install` and `fprint-sleep-install`
   - `smart-charge-install`, only if the battery supports a charge limit
   - fingerprint for sudo
   - NumLock on at the login screen
   - Arch's network check
   - `larp`
   - Wi-Fi, Bluetooth, power profiles, SSD trim, and SDDM (only if no login screen is set up yet)
8. **Builds:** the hymission window overview (via `arch-update --build-hymission`), Spun and its YouTube helper,
   boardroom (via `uv`), Claude Code with the chat-tools mod, and the VS Code extensions.
9. **Look and services:** GTK theme, icons, fonts and cursor (`extra/dconf-interface.ini`), and your user services:
   Bluetooth agent, Syncthing, news brief and update check.

## What's in here

| Folder | What |
| --- | --- |
| `home/` | Files copied into `~`, at the same paths (`.config/hypr`, `.config/quickshell`, `.config/caelestia`, `.local/bin`, `.local/src/…`, `Pictures/Wallpapers`, `.bashrc`…) |
| `packages/` | Package lists (pacman, AUR, Flatpak, VS Code) and the pinned caelestia-cli recipe |
| `system/` | The few `/etc` and `/usr/local` files that none of the `*-install` scripts create |
| `extra/` | GTK settings (dconf) |

## Left out on purpose

- **Logins and keys:** browsers, Discord/Vesktop, Bitwarden, Thunderbird, Obsidian, the GitHub and Claude sign-ins,
  SSH/GPG keys, Syncthing keys, Wi-Fi passwords. Sign in again.
- **Machine-specific things:** the VM tools and their disks (`vm`, `fedora-vm`, `/mnt/data`), the partition tools
  for this laptop's disk, the Steam library, Claude Code chats and memory.
- **Big or rebuildable things:** build folders, Python venvs, `rice-snapshots`, notification history, recordings,
  and any file over 20 MB. `sync.sh` lists those each time it runs.
- **The disabled rice pieces:** `rice-install` isn't run, because the rice was rolled back on 2026-10-12. Only the
  bar, panels and animations are kept, and those are in the configs.

If the new machine has different screens, press F7 to arrange them. Hardware the new machine doesn't have
(fingerprint reader, charge limit, ThinkPad fan) is skipped or does nothing.
