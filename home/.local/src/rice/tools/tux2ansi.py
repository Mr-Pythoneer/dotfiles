#!/usr/bin/env python3
"""Turn Tux.svg into a half-block ANSI logo in the terminal's graphite palette.

usage: tux2ansi.py Tux.svg rows out.ansi [widen]
widen stretches Tux sideways (1.0 = the artwork's own shape). The pupils are black like his fur, which
would come out as the same grey as his body (white rings, like a monocle), so they're recoloured to a marker
in a copy of the SVG first and drawn near-black.
Each character cell is 1x2 pixels (upper half = foreground, lower half = background colour of ▀).
"""
import colorsys
import subprocess
import sys
import tempfile

from PIL import Image

PALETTE = {  # what each part of Tux becomes
    "body": (98, 102, 110),     # black fur -> mid grey, visible on the #17181b background
    "shade": (62, 65, 71),      # dark outline / shadows
    "belly": (212, 212, 208),   # white -> the terminal's off-white foreground
    "beak": (196, 168, 106),    # yellow/orange -> the palette's muted sand (color3)
    "pupil": (14, 14, 17),      # near-black, darker than the fur grey
}


def classify(r, g, b, a):
    if a < 110:
        return None
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    if s > 0.5 and 0.78 < h < 0.9 and l > 0.2:   # the magenta marker on the pupils (pinkish at the edges)
        return "pupil"
    if s > 0.6 and 0.03 < h < 0.2 and 0.2 < l < 0.8:   # not the pale-yellow belly highlights
        return "beak"
    if l > 0.55:
        return "belly"
    if l < 0.1:
        return "shade"
    return "body"


def build_grid(svg, rows, widen=1.0):
    """Tux as rows of pixel names (None = see-through). tux-variants.py edits these before render()."""
    hpx = int(rows) * 2
    wpx = round(hpx * 216 / 256 * float(widen))
    marked = open(svg).read()
    for side in ("left", "right"):
        marked = marked.replace(f'id="pupil_{side}_base" fill="#020204"', f'id="pupil_{side}_base" fill="#ff00ff"')
    with tempfile.NamedTemporaryFile(suffix=".png") as big, tempfile.NamedTemporaryFile("w", suffix=".svg") as m:
        m.write(marked)
        m.flush()
        subprocess.run(["rsvg-convert", "-h", str(hpx * 8), "-o", big.name, m.name], check=True)
        img = Image.open(big.name).convert("RGBA").resize((wpx, hpx), Image.LANCZOS)
    px = img.load()
    grid = [[classify(*px[x, y]) for x in range(wpx)] for y in range(hpx)]
    for y in range(hpx // 3, hpx):  # the eyes are in the top third; faint purple shading lower down is fur
        grid[y] = ["body" if c == "pupil" else c for c in grid[y]]
    return grid


def render(grid, palette=PALETTE):
    """Pixel names -> half-block ANSI text, two pixel rows per text line."""
    lines = []
    for y in range(0, len(grid), 2):
        line = ""
        for x in range(len(grid[0])):
            top = grid[y][x]
            bot = grid[y + 1][x]
            if top is None and bot is None:
                line += "\x1b[0m "
            elif top is None:
                line += "\x1b[0m\x1b[38;2;%d;%d;%dm▄" % palette[bot]
            elif bot is None:
                line += "\x1b[0m\x1b[38;2;%d;%d;%dm▀" % palette[top]
            elif top == bot:
                line += "\x1b[0m\x1b[38;2;%d;%d;%dm█" % palette[top]
            else:
                line += "\x1b[38;2;%d;%d;%dm\x1b[48;2;%d;%d;%dm▀" % (palette[top] + palette[bot])
        lines.append(line.rstrip() + "\x1b[0m")
    while lines and lines[-1].replace("\x1b[0m", "").strip() == "":
        lines.pop()
    return "\n".join(lines) + "\n"


def main(svg, rows, out, widen="1.0"):
    with open(out, "w") as f:
        f.write(render(build_grid(svg, rows, widen)))


if __name__ == "__main__":
    main(*sys.argv[1:5])
