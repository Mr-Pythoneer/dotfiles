# Rice assets (2026-10-10)

Human-made wallpapers for the rice, recoloured per palette with lutgen.

- `originals/`: the sources, 1920 wide. git-live/git-still = Gource frames of hyprwm/Hyprland history;
  source-a = Ilya Pavlov, source-b = Chris Ried, rain-b = Markus Spiske (all Unsplash License);
  circuit-a/b = D3Ext/aesthetic-wallpapers; ascii-a = sasvi, KDE Store 1442413 (GPL-2.0+).
- Rendered per palette (not lutgen): rain-a = Rezmason/matrix (MIT, clone it again and serve it);
  skyline-a = gh-skyline STL (`gh skyline --year 2026`) rendered by `tools/render.html` via `tools/render1.sh`.
- `tools/pipeline.py` regenerates everything (expects the original scratchpad layout; paths need adjusting).
- `tools/lutgen`: lutgen-cli v1.1.1 from ozwaldorf/lutgen-rs releases.
- `picker/`: the published picker page (https://claude.ai/artifact/8iY6TkTWD83tSfXFLM6bSN) + its images.
- Gource ran from a local unpack of the Arch package (glew + sdl2_image missing system-wide); for a live
  wallpaper install it properly: `sudo pacman -S gource`.
  ascii-fedora (Fedora VM only, ~/Pictures/Wallpapers/fedora) = Fedora's neofetch ASCII logo (neofetch, MIT, Dylan Araps), set like ascii-a by tools/ascii-fedora.py.
  Tux.svg = Larry Ewing's Tux (Wikimedia Commons, free with credit), made into ~/.config/fastfetch/tux.ansi by tools/tux2ansi.py: `tux2ansi.py originals/Tux.svg 18 ~/.config/fastfetch/tux.ansi 1.3` (rows, widen).
  Tux variants (tiny easter eggs) for fastfetch: tools/tux-variants.py -> ~/.config/fastfetch/tux/*.ansi; fastfetch() in ~/.bashrc picks one (plain ~50%, MM-name only in month MM).
