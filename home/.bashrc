#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Fedora keeps bash-completion and the /etc/profile.d hooks in /etc/bashrc (Arch has no such file)
[ -f /etc/bashrc ] && . /etc/bashrc

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '
export PATH="$HOME/.local/bin:$PATH"

# --- terminal eye candy ---------------------------------------------------
# New terminals open with a random cowsay character saying a random fortune (cowtune).
# Switch with: eyecandy on | off. The animated scenes are still there: archfetch, scene NAME.
[[ $(cat "${XDG_CONFIG_HOME:-$HOME/.config}/eyecandy/mode" 2>/dev/null) == off ]] && EYECANDY_OFF=1
if [[ -z $EYECANDY_OFF && $SHLVL -le 1 ]] && command -v cowtune >/dev/null; then
    cowtune
fi
alias archfetch='archboot --no-boot'   # replay the splash without boot lines
alias scene='archboot --no-boot --scene'  # e.g. scene donut  (archboot --list for all)
# the fun CLI tools, in the desktop's look (neither has a settings file, so their defaults live here)
alias cmatrix='cmatrix -b -a -C white'   # mono: white heads, grey trails, bold, columns at their own speeds
# fastfetch shows a random Tux: plain about half the time, otherwise with one tiny hidden detail. The variants
# come from ~/.local/src/rice/tools/tux-variants.py; "MM-name" ones only turn up in month MM (pumpkin, Santa hat).
fastfetch() {
    local d=~/.config/fastfetch/tux f pick
    local -a extra=()
    if [[ ! -f $d/plain.ansi ]]; then command fastfetch "$@"; return; fi
    for f in "$d"/*.ansi; do
        case ${f##*/} in
            plain.ansi) ;;
            [0-9][0-9]-*) [[ ${f##*/} == $(date +%m)-* ]] && extra+=("$f") ;;
            *) extra+=("$f") ;;
        esac
    done
    pick=$d/plain.ansi
    (( ${#extra[@]} && RANDOM % 100 < 50 )) && pick=${extra[RANDOM % ${#extra[@]}]}
    command fastfetch --logo "$pick" "$@"
}
# heavy pipes in the soft accents (blue, mauve, teal, green, amber, peach, red as their nearest 256-colour numbers)
alias pipes.sh='pipes.sh -t 0 -c 111 -c 183 -c 116 -c 150 -c 223 -c 216 -c 210'

# two-line prompt in the distro's blue (Arch, or Fedora in the VM); arrow turns red when the last command failed
__brand_rgb='23;147;209'
grep -q '^ID=fedora' /etc/os-release 2>/dev/null && __brand_rgb='81;162;218'
__eyecandy_prompt() {
    local s=$? blue="\[\e[38;2;${__brand_rgb}m\]" dim='\[\e[38;2;90;90;110m\]' r='\[\e[0m\]'
    local arrow='\[\e[38;2;80;250;123m\]'; ((s)) && arrow='\[\e[38;2;255;85;85m\]'
    PS1="${dim}╭─${blue}\u@\h${dim}─[${r}\w${dim}]${r}\n${dim}╰─${arrow}▶${r} "
}
PROMPT_COMMAND=__eyecandy_prompt

# Claude Code never saves "trust" for the home folder itself, so start it from ~/.claude-home
# (trusted once) with the whole home folder added
claude() {
    case "$1" in agents|attach|auth|auto-mode|doctor|gateway|import|install|logs|mcp|plugin|plugins|purge|respawn|rm|setup-token|stop|kill|ultrareview|update|upgrade) command claude "$@"; return;; esac
    if [ "$PWD" = "$HOME" ]; then (cd ~/.claude-home && command claude "$@" --add-dir "$HOME"); else command claude "$@"; fi
}
