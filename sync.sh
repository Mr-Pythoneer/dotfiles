#!/bin/bash
# Run on THIS laptop: copies your desktop into the repo (home/, packages/, system/), checks the copy for
# anything that looks like a password or token, and with --push commits and pushes it to GitHub.
#     ./sync.sh            refresh the repo from this machine
#     ./sync.sh --push     the same, then commit and push
# Logins stay out on purpose: browsers, chat apps, Bitwarden, GitHub/Claude sign-ins, SSH/GPG keys, Syncthing
# keys, Wi-Fi passwords. Sign in again on the new machine.
set -euo pipefail
REPO=$(cd "$(dirname "$0")" && pwd)
PUSH=0
[ "${1:-}" = --push ] && PUSH=1
cd "$HOME"

# What gets copied, relative to ~
items=(
    # the desktop: Hyprland, the Caelestia shell (patched copy + patches), the rice bar, terminal, look
    .config/hypr .config/quickshell .config/caelestia .config/kitty .config/fastfetch .config/gtk-3.0
    .config/gtk-4.0 .config/qt6ct .config/qtengine .config/Kvantum .config/fontconfig .config/wlogout
    .config/fuzzel .config/swaylock .config/waypaper .config/eyecandy .config/nwg-displays .config/autostart
    .config/mimeapps.list .config/user-dirs.dirs .config/user-dirs.locale .config/systemd/user
    # apps
    .config/btop .config/cava .config/fcitx5 .config/superfile .config/solaar .config/spun .config/mpv
    .config/zathura .config/htop .config/nvtop .config/kew .config/Mousepad .config/procps .config/zed
    .config/Code/User/settings.json .config/Code/User/keybindings.json
    # your own tools and their settings
    .local/bin .config/update-check .config/boardroom
    .local/src/news-brief .local/src/update-check .local/src/rice .local/src/claude-chat-tools
    .local/src/boardroom
    .local/share/applications .local/share/rice .local/share/spun .local/share/arch-kit .local/share/icons
    .local/share/fcitx5 .local/share/superfile
    .local/state/caelestia .local/state/smart-charge .local/state/first-login-done
    .claude/settings.json
    Pictures/Wallpapers .icons .bashrc .bash_profile .bash_logout
)
# ~/.local/bin entries that don't belong on another machine: installed separately (claude, uv, boardroom),
# built by install.sh (hymission-search-input), the VM tools (their disks live on /mnt/data), and the
# partition tools for this laptop's disk
skip_bin=(claude uv uvx boardroom hymission-search-input vm fedora-vm merge-data-drives shrink-fedora-make-storage)
excludes=(
    --exclude=.git/ --exclude=__pycache__/ --exclude='*.pyc' --exclude=node_modules/ --exclude=.venv/
    --exclude='*.bak' --exclude='*.bak-*' --exclude='*.bak.*' --exclude='*.archinstall' --exclude='*.orig'
    --exclude='*.rej'
    --exclude=/.local/state/caelestia/notifs.json --exclude=/.local/state/caelestia/record/
    --exclude=/.local/share/spun/build/ --exclude=/.local/share/spun/runtime/ --exclude=/.local/src/rice/unused/
    --exclude='/.local/share/applications/vm-*' --exclude='/.local/share/applications/fedora-*vm*'
    --exclude='/.local/share/applications/*-vm.desktop'
)
for n in "${skip_bin[@]}"; do excludes+=(--exclude="/.local/bin/$n"); done
# GitHub refuses files over 100 MB and the repo gets slow well before that
MAX=20m

step() { printf '==> %s\n' "$*"; }

step "Copying your files"
present=()
for i in "${items[@]}"; do
    if [ -e "$i" ] || [ -L "$i" ]; then present+=("$i"); fi
done
rm -rf "$REPO/home"
mkdir -p "$REPO/home"
rsync -aR --max-size=$MAX "${excludes[@]}" "${present[@]}" "$REPO/home/"
# links into your home become relative, so they work under any user name
find "$REPO/home" -type l | while read -r link; do
    target=$(readlink "$link")
    case "$target" in
        "$HOME"/*)
            rel=${link#"$REPO/home/"}
            ln -sfn "$(realpath -m --relative-to="$(dirname "$HOME/$rel")" "$target")" "$link" ;;
    esac
done
big=$(find "${present[@]}" -type f -size +20M -not -path '*/.git/*' -not -path '*/build/*' \
      -not -path '*/runtime/*' -not -path '.local/src/rice/unused/*' 2>/dev/null \
      | grep -v -x -F -f <(printf '.local/bin/%s\n' "${skip_bin[@]}") || true)

step "Package lists"
mkdir -p "$REPO/packages"
pacman -Qqen > "$REPO/packages/pacman.txt"
# every AUR package (dependencies too: several aren't in the repos), minus debug symbols, yay itself and
# the three that install.sh builds from exact recipes: the two in .local/share/arch-kit, and caelestia-cli,
# which pacman.conf holds at the version the top bar was tested with
pacman -Qqm | grep -v -E -- '-debug$|^(yay-bin|quickshell-pinned|caelestia-shell-topbar|caelestia-cli)$' \
    > "$REPO/packages/aur.txt"
rm -rf "$REPO/packages/pinned"
mkdir -p "$REPO/packages/pinned/caelestia-cli"
cp ~/.cache/yay/caelestia-cli/PKGBUILD ~/.cache/yay/caelestia-cli/*.install "$REPO/packages/pinned/caelestia-cli/"
flatpak list --app --columns=application 2>/dev/null | sed '/^$/d' > "$REPO/packages/flatpak.txt" || true
command -v code >/dev/null && code --list-extensions 2>/dev/null > "$REPO/packages/vscode.txt" || true

step "System files and GTK settings"
rm -rf "$REPO/system"
for f in /etc/sddm.conf.d/numlock.conf /etc/NetworkManager/conf.d/20-connectivity.conf /usr/local/bin/larp; do
    if [ -e "$f" ]; then install -D -m "$(stat -c %a "$f")" "$f" "$REPO/system$f"; fi
done
mkdir -p "$REPO/extra"
dconf dump /org/gnome/desktop/interface/ > "$REPO/extra/dconf-interface.ini" 2>/dev/null || true

step "Checking for passwords and tokens"
# patterns that are almost always a real secret: stop before anything gets committed
sure='gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{40,}'
sure+='|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|xox[abposr]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
hits=$(grep -rIlE "$sure" "$REPO/home" "$REPO/system" 2>/dev/null || true)
if [ -n "$hits" ]; then
    echo "Stopped: these look like they contain a token or private key:"
    echo "$hits" | sed "s|$REPO/||; s/^/    /"
    echo "Remove them from the list in sync.sh (or from the file), then run it again."
    exit 1
fi

files=$(find "$REPO/home" -type f | wc -l)
size=$(du -sh --exclude=.git "$REPO" | cut -f1)
echo "    none found. $files files, $size"
if [ -n "$big" ]; then
    echo "    left out (over 20 MB):"
    echo "$big" | sed 's/^/        ~\//'
fi

if [ "$PUSH" = 1 ]; then
    step "Commit and push"
    cd "$REPO"
    git add -A
    if git diff --cached --quiet; then
        echo "    nothing changed since the last sync"
    else
        git commit -q -m "Sync from $(hostname) $(date '+%Y-%m-%d %H:%M')"
        git push -q
        echo "    pushed: $(git log -1 --format='%h %s')"
    fi
fi
