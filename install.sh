#!/bin/bash
# Run on the NEW machine (a fresh Arch with Hyprland): puts this desktop on it. That means your apps, the
# Caelestia shell with your patches and top bar, the rice bar, Hyprland settings and keybinds, your scripts
# and little systems (power modes, smart charging, news brief, update check, Bluetooth agent...), wallpapers
# and the whole look.
#     ./install.sh               everything; asks for your password once
#     ./install.sh --files-only  only copy configs and scripts (no packages, no password)
# Safe to run again. Anything it replaces in your home is kept in ~/.local/state/dotfiles-backup/<date>/.
set -uo pipefail
REPO=$(cd "$(dirname "$0")" && pwd)
OLD_HOME=/home/mrpythoneer   # the home these files were copied from
FILES_ONLY=0
case "${1:-}" in
    --files-only) FILES_ONLY=1 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "") ;;
    *) echo "unknown option: $1 (try --help)"; exit 1 ;;
esac
[ "$(id -u)" != 0 ] || { echo "Run it as yourself, not with sudo (it asks for your password when it needs it)."; exit 1; }
[ -f /etc/arch-release ] || { echo "This is for Arch Linux."; exit 1; }

LOGS=~/.cache/dotfiles-install
mkdir -p "$LOGS"
exec > >(tee -a "$LOGS/install.log") 2>&1

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32mok\033[0m      %s\n' "$*"; }
bad()  { printf '    \033[31mPROBLEM\033[0m %s\n' "$*"; problems+=("$*"); }
note() { printf '    %s\n' "$*"; }
problems=()
# a package list without comments and blank lines
pkgs() { sed 's/#.*//; /^[[:space:]]*$/d' "$REPO/packages/$1" 2>/dev/null; }
YAY=(yay --needed --noconfirm --answerdiff None --answerclean None --removemake)

pacman_conf() {
    step "pacman settings"
    # caelestia-cli stays at the version the top bar was tested with (arch-update relies on this)
    if grep -qE '^IgnorePkg *=.*\bcaelestia-cli\b' /etc/pacman.conf; then
        :
    elif grep -qE '^IgnorePkg *=' /etc/pacman.conf; then
        sudo sed -i 's/^\(IgnorePkg *=.*\)$/\1 caelestia-cli/' /etc/pacman.conf
    else
        sudo sed -i '/^\[options\]/a IgnorePkg = caelestia-cli' /etc/pacman.conf
    fi
    grep -q '^Color' /etc/pacman.conf || sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
    ok "caelestia-cli held at the tested version, colour on"
}

repo_packages() {
    step "Arch packages ($(pkgs pacman.txt | wc -l) on your list)"
    sudo pacman -Syu --noconfirm || { bad "the system update failed, so no packages were added"; return; }
    local want avail missing
    want=$(printf '%s\n' $(pkgs pacman.txt) base-devel git rsync cmake ninja | sort -u)
    avail=$(comm -12 <(echo "$want") <(pacman -Slq | sort -u))
    missing=$(comm -23 <(echo "$want") <(echo "$avail"))
    [ -z "$missing" ] || note "no longer in Arch's repos, skipped: $(echo $missing)"
    # --ask 4 says yes when a package replaces one it conflicts with (pipewire-jack for jack2, say)
    if ! sudo pacman -S --needed --noconfirm --ask 4 $avail; then
        note "installing them all at once failed; trying one at a time"
        for p in $avail; do
            sudo pacman -S --needed --noconfirm --ask 4 "$p" >>"$LOGS/pacman.log" 2>&1 || bad "pacman couldn't install $p"
        done
    fi
    ok "Arch packages"
}

aur_packages() {
    step "AUR packages ($(pkgs aur.txt | wc -l) on your list)"
    if ! command -v yay >/dev/null; then
        local t; t=$(mktemp -d)
        if git clone -q https://aur.archlinux.org/yay-bin.git "$t/yay-bin" \
            && (cd "$t/yay-bin" && makepkg -si --noconfirm) >"$LOGS/yay.log" 2>&1; then
            ok yay
        else
            bad "couldn't install yay, so there are no AUR packages (log: $LOGS/yay.log)"; rm -rf "$t"; return
        fi
        rm -rf "$t"
    fi
    local list; list=$(pkgs aur.txt)
    if ! "${YAY[@]}" -S $list; then
        note "installing them all at once failed; trying one at a time"
        for p in $list; do
            pacman -Qq "$p" >/dev/null 2>&1 && continue
            "${YAY[@]}" -S "$p" >>"$LOGS/aur.log" 2>&1 || bad "the AUR package $p didn't install (log: $LOGS/aur.log)"
        done
    fi
    ok "AUR packages"
}

# Builds a PKGBUILD folder and installs the result, replacing whatever it conflicts with (the official
# Caelestia or Quickshell, if this machine came with them). Dependencies that aren't in Arch's repos
# come from the AUR first. Same recipe as arch-update --build-local.
build_recipe() {
    local dir=$1 name=$2 t
    if pacman -Qq "$name" >/dev/null 2>&1; then ok "$name (already installed)"; return; fi
    note "building $name..."
    # not /tmp: that's RAM, and Quickshell's build takes ~2.5 GB
    t=$(mktemp -d -p /var/tmp "dotfiles-$name.XXXX")
    cp -r "$dir/." "$t/"
    if (
        cd "$t" || exit 1
        deps=$(bash -c 'source ./PKGBUILD; printf "%s\n" "${depends[@]}" "${makedepends[@]}"' | sed 's/[<>=].*//')
        missing=$(pacman -T $deps)
        aur=$(for d in $missing; do pacman -Si "$d" >/dev/null 2>&1 || echo "$d"; done)
        [ -z "$aur" ] || "${YAY[@]}" -S --asdeps $aur || exit 1
        makepkg -sf --noconfirm || exit 1
        sudo pacman -U --noconfirm --ask 4 $(ls ./*.pkg.tar.zst | grep -v -- '-debug-')
    ) >"$LOGS/$name.log" 2>&1; then
        ok "$name"
    else
        bad "$name didn't build (log: $LOGS/$name.log)"
    fi
    rm -rf "$t"
}

caelestia_stack() {
    step "Caelestia with your top bar, on the Quickshell it was tested with"
    build_recipe "$REPO/packages/pinned/caelestia-cli" caelestia-cli
    build_recipe "$REPO/home/.local/share/arch-kit/pkg/quickshell-pinned" quickshell-pinned
    build_recipe "$REPO/home/.local/share/arch-kit/pkg/caelestia-shell-topbar" caelestia-shell-topbar
}

flatpaks() {
    local apps; apps=$(pkgs flatpak.txt)
    [ -n "$apps" ] || return
    step "Flatpak apps"
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    for app in $apps; do
        sudo flatpak install -y --noninteractive flathub "$app" >>"$LOGS/flatpak.log" 2>&1 && ok "$app" \
            || bad "the Flatpak $app didn't install (log: $LOGS/flatpak.log)"
    done
}

copy_files() {
    step "Your configs, scripts, wallpapers and settings"
    local bk; bk=~/.local/state/dotfiles-backup/$(date +%Y%m%d-%H%M%S)
    local n=0 kept=0 src rel dst
    while IFS= read -r -d '' src; do
        rel=${src#"$REPO/home/"}
        dst=$HOME/$rel
        if [ -e "$dst" ] || [ -L "$dst" ]; then
            # already the same: leave it alone
            if [ -L "$src" ] && [ -L "$dst" ] && [ "$(readlink "$src")" = "$(readlink "$dst")" ]; then continue; fi
            if [ ! -L "$src" ] && [ ! -L "$dst" ] && [ -f "$dst" ] && cmp -s "$src" "$dst"; then continue; fi
            mkdir -p "$bk/$(dirname "$rel")" && cp -a "$dst" "$bk/$rel" && kept=$((kept + 1))
        fi
        mkdir -p "$(dirname "$dst")"
        cp -a --remove-destination "$src" "$dst" && n=$((n + 1))
    done < <(find "$REPO/home" \( -type f -o -type l \) -print0)
    ok "$n files copied"
    [ "$kept" = 0 ] || note "the $kept files they replaced are in $bk"

    # a different user name: point paths inside the files at this home
    if [ "$HOME" != "$OLD_HOME" ]; then
        local fixed=0
        while IFS= read -r -d '' src; do
            rel=${src#"$REPO/home/"}
            if grep -qsF "$OLD_HOME" "$HOME/$rel"; then
                sed -i "s|$OLD_HOME|$HOME|g" "$HOME/$rel" && fixed=$((fixed + 1))
            fi
        done < <(find "$REPO/home" -type f -print0 | xargs -0 grep -lIZF "$OLD_HOME" 2>/dev/null)
        ok "$fixed files changed from $OLD_HOME to $HOME"
    fi
    # your folders (Desktop, Projects...) have to exist, or xdg-user-dirs-update points them back at ~
    sed -n 's/^XDG_[A-Z]*_DIR="\$HOME\/\(.*\)"$/\1/p' ~/.config/user-dirs.dirs 2>/dev/null \
        | while read -r d; do mkdir -p "$HOME/$d"; done
    mkdir -p ~/Pictures/Screenshots ~/.claude-home
    command -v xdg-user-dirs-update >/dev/null && xdg-user-dirs-update
}

system_setup() {
    step "System settings"
    local f
    while IFS= read -r f; do
        f=${f#.}
        sudo install -D -m "$(stat -c %a "$REPO/system$f")" "$REPO/system$f" "$f" && ok "$f"
    done < <(cd "$REPO/system" && find . -type f)
    # sudo takes your fingerprint as well as your password
    if pacman -Qq fprintd >/dev/null 2>&1 && ! grep -q pam_fprintd /etc/pam.d/sudo; then
        sudo sed -i '0,/^auth/s//auth\t\tsufficient\tpam_fprintd.so\nauth/' /etc/pam.d/sudo && ok "fingerprint for sudo"
    fi
    for i in power-tweaks-install eco-mode-install fprint-sleep-install; do
        sudo ~/.local/bin/$i >>"$LOGS/system.log" 2>&1 && ok "$i" || bad "$i failed (log: $LOGS/system.log)"
    done
    if [ -e /sys/class/power_supply/BAT0/charge_control_end_threshold ]; then
        sudo ~/.local/bin/smart-charge-install >>"$LOGS/system.log" 2>&1 && ok smart-charge-install \
            || bad "smart-charge-install failed (log: $LOGS/system.log)"
    else
        note "this machine has no battery charge limit, so smart charging stays off"
    fi
    sudo systemctl enable NetworkManager.service bluetooth.service power-profiles-daemon.service fstrim.timer \
        >>"$LOGS/system.log" 2>&1 && ok "Wi-Fi, Bluetooth, power profiles and SSD trim services on" \
        || bad "couldn't switch on the system services (log: $LOGS/system.log)"
    # a login screen, unless this install already has one
    if ! systemctl is-enabled display-manager.service >/dev/null 2>&1; then
        sudo systemctl enable sddm.service >>"$LOGS/system.log" 2>&1 && ok "SDDM login screen on"
    fi
}

builds() {
    step "Things built for this machine"
    ~/.local/bin/arch-update --build-hymission >"$LOGS/hymission.log" 2>&1
    [ -f ~/.local/lib/hyprland/libhymission.so ] && ok "window overview plugin (hymission)" \
        || bad "the window overview plugin didn't build; Super+Tab overview is off (log: ~/.cache/arch-update/hymission.log)"
    if (cd ~/.local/share/spun && rm -rf build && ./scripts/build.sh && ./scripts/setup-youtube.sh) >"$LOGS/spun.log" 2>&1; then
        ok "Spun"
    else
        bad "Spun didn't build (log: $LOGS/spun.log)"
    fi
    uv tool install --editable ~/.local/src/boardroom >"$LOGS/boardroom.log" 2>&1 && ok boardroom \
        || bad "boardroom didn't install (log: $LOGS/boardroom.log)"

    if ! command -v claude >/dev/null && [ ! -x ~/.local/bin/claude ]; then
        curl -fsSL https://claude.ai/install.sh | bash >"$LOGS/claude.log" 2>&1 || bad "Claude Code didn't install (log: $LOGS/claude.log)"
    fi
    if [ -x ~/.local/bin/claude ]; then
        ~/.local/bin/claude plugin marketplace add ~/.local/src/claude-chat-tools >>"$LOGS/claude.log" 2>&1
        ~/.local/bin/claude plugin install chat-tools@claude-chat-tools --scope user >>"$LOGS/claude.log" 2>&1
        ok "Claude Code and your /chats /pin /delete commands"
    fi
    if command -v code >/dev/null; then
        for e in $(pkgs vscode.txt); do
            code --install-extension "$e" >>"$LOGS/vscode.log" 2>&1 || bad "VS Code extension $e"
        done
        ok "VS Code extensions"
    fi
}

look_and_services() {
    step "Look and your background services"
    local ini=$REPO/extra/dconf-interface.ini
    if [ -s "$ini" ]; then
        # outside a desktop session (a text console) dconf needs a bus of its own
        if dconf load /org/gnome/desktop/interface/ < "$ini" 2>/dev/null \
            || dbus-run-session dconf load /org/gnome/desktop/interface/ < "$ini" 2>/dev/null; then
            ok "GTK theme, icons, fonts and cursor"
        else
            bad "couldn't apply the GTK theme settings"
        fi
    fi
    fc-cache -f >/dev/null 2>&1
    if systemctl --user daemon-reload 2>/dev/null; then
        for u in bluetooth-agent.service syncthing.service news-brief.timer update-check.timer; do
            systemctl --user enable "$u" >/dev/null 2>&1 && ok "$u" || bad "couldn't switch on $u"
        done
    else
        note "no user session yet: your services switch on at your first login (their links were copied)"
    fi
}

if [ "$FILES_ONLY" = 0 ]; then
    echo "This installs a lot (about 200 packages and three builds) and takes 30-60 minutes."
    sudo -v || exit 1
    # keep sudo from timing out during the long builds
    ( while kill -0 $$ 2>/dev/null; do sudo -n true; sleep 50; done ) 2>/dev/null &
    pacman_conf
    repo_packages
    aur_packages
    caelestia_stack
    flatpaks
fi
copy_files
if [ "$FILES_ONLY" = 0 ]; then
    system_setup
    builds
fi
look_and_services

step "Done"
if [ ${#problems[@]} -eq 0 ]; then
    echo "    Everything worked."
else
    echo "    ${#problems[@]} thing(s) need a look:"
    printf '      - %s\n' "${problems[@]}"
fi
cat <<'EOF'

    Then:
      1. Reboot (or log out and pick Hyprland) to start everything.
      2. fprintd-enroll                       if this machine has a fingerprint reader
      3. claude                               sign in once (the news brief and update fixes use it)
      4. Sign in to Chrome, Zen, Thunderbird, VS Code, Vesktop, Obsidian and Bitwarden
      5. Syncthing (localhost:8384): pair your devices again; this machine has a new ID
      6. Different screens? Press F7 to arrange them
    Full log: ~/.cache/dotfiles-install/install.log
EOF
