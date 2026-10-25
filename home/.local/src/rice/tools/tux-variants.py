#!/usr/bin/env python3
"""The fastfetch Tux with tiny hidden details: a wink, a glance, a blush, a heart, a fish, snowflakes, a mug,
a bowtie, a twinkle, and two seasonal ones (October pumpkin, December Santa hat). One or two pixels each,
easy to miss unless you look. fastfetch() in ~/.bashrc picks one at random each run, plain most of the time;
files named "MM-name.ansi" only show up in month MM.

    tux-variants.py [OUTDIR]      (default ~/.config/fastfetch/tux; same size as tux2ansi: 18 rows, 1.3 wide)
"""
import copy
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tux2ansi", os.path.join(HERE, "tux2ansi.py"))
t2a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(t2a)

PALETTE = dict(t2a.PALETTE, **{
    "pink": (226, 150, 160),    # blush
    "faint": (232, 190, 196),   # the heart: barely pinker than the belly it's on
    "slate": (127, 152, 181),   # the fish, the mug (the terminal palette's blue)
    "snow": (232, 232, 228),
    "red": (190, 70, 80),       # bowtie, Santa hat
    "knot": (130, 45, 55),      # the bowtie's middle
    "orange": (232, 150, 90),   # pumpkin
    "leaf": (143, 168, 130),    # pumpkin stem (the palette's sage)
})


def cells(grid, name):
    return [(x, y) for y, row in enumerate(grid) for x, c in enumerate(row) if c == name]


def put(grid, x, y, name, only=None):
    """Paint one pixel if it's inside the picture (and, with `only`, if it's currently one of those)."""
    if 0 <= y < len(grid) and 0 <= x < len(grid[0]) and (only is None or grid[y][x] in only):
        grid[y][x] = name


def stamp(grid, x0, y0, rows, colours, only=None):
    for dy, row in enumerate(rows):
        for dx, ch in enumerate(row):
            if ch != ".":
                put(grid, x0 + dx, y0 + dy, colours[ch], only)


def free_spot(grid, rows, xs, ys):
    """The first top-left corner (scanning ys, then xs) where a stamp of `rows` lands only on empty pixels."""
    w, h = max(map(len, rows)), len(rows)
    for y in ys:
        for x in xs:
            if all(0 <= y + dy < len(grid) and 0 <= x + dx < len(grid[0]) and grid[y + dy][x + dx] is None
                   for dy, row in enumerate(rows) for dx, ch in enumerate(row) if ch != "."):
                return x, y
    return None


class Features:
    """Where things are, found from the pixels so the details still land right at another size."""

    def __init__(self, g):
        h, w = len(g), len(g[0])
        pupils = cells(g, "pupil")
        mid = sum(x for x, _ in pupils) / len(pupils)
        self.eyes = []
        for side in (lambda x: x < mid, lambda x: x >= mid):  # viewer's left eye, then right
            ps = [(x, y) for x, y in pupils if side(x)]
            x0, x1 = min(x for x, _ in ps) - 1, max(x for x, _ in ps) + 1
            y0, y1 = min(y for _, y in ps) - 1, max(y for _, y in ps)
            whites = [(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)
                      if g[y][x] in ("belly", "pupil")]
            self.eyes.append({"pupils": ps, "cells": whites, "x0": x0, "x1": x1, "y0": y0, "y1": y1})
        beak = [(x, y) for x, y in cells(g, "beak") if y < h // 2]
        self.beak = (min(x for x, _ in beak), min(y for _, y in beak), max(x for x, _ in beak), max(y for _, y in beak))
        belly = [(x, y) for x, y in cells(g, "belly") if y > self.beak[3]]
        self.belly = (min(x for x, _ in belly), min(y for _, y in belly), max(x for x, _ in belly), max(y for _, y in belly))
        head = [(x, y) for x, y in cells(g, "shade") + cells(g, "body") if y <= 1]
        self.head = (min(x for x, _ in head), max(x for x, _ in head))
        self.w, self.h = w, h


def wink(g, f):
    e = f.eyes[0]
    for x, y in e["cells"]:
        g[y][x] = "shade"
    for x in range(e["x0"] + 1, e["x1"]):  # a closed lid
        put(g, x, e["y1"] - 1, "pupil")


def glance(g, f):
    for e in f.eyes:  # pupils one pixel to the side, as if something caught his eye
        moved = [(x - 1, y) for x, y in e["pupils"]]
        if all(g[y][x] in ("belly", "pupil") for x, y in moved):
            for x, y in e["pupils"]:
                g[y][x] = "belly"
            for x, y in moved:
                g[y][x] = "pupil"


def blush(g, f):
    for e, out in ((f.eyes[0], -1), (f.eyes[1], 1)):  # one pink pixel just outside each eye, low down
        edge = e["x0"] if out < 0 else e["x1"]
        for x, y in ((edge + out, e["y1"] + 1), (edge + out, e["y1"]), (edge, e["y1"] + 1), (edge + 2 * out, e["y1"])):
            if 0 <= y < f.h and 0 <= x < f.w and g[y][x] in ("body", "shade"):
                g[y][x] = "pink"
                break


def heart(g, f):
    x0, y0, _, _ = f.belly
    stamp(g, x0 + 4, y0 + 6, ["PP.PP", "PPPPP", ".PPP.", "..P.."], {"P": "faint"}, only=("belly",))


def fish(g, f):
    shape = ["F.FF.", ".FFFF", "F.FF."]  # forked tail on the left, swimming right
    spot = free_spot(g, shape, range(f.w - 5, f.w // 2, -1), range(f.h - 3, f.h - 8, -1))
    if spot:
        stamp(g, *spot, shape, {"F": "slate"})


def snow(g, f):
    for x, y in ((f.head[0] - 6, 1), (f.head[1] + 7, 3), (f.head[1] + 3, 0), (f.head[0] - 5, 9)):
        put(g, x, y, "snow", only=(None,))


def coffee(g, f):
    shape = [".S..", "....", "MMM.", "MMMM", "MMM."]  # a wisp of steam over a mug with a handle
    spot = free_spot(g, shape, range(f.w - 4, f.w // 2, -1), range(f.h // 2, f.h - 5))
    if spot:
        stamp(g, *spot, shape, {"S": "snow", "M": "slate"})


def bowtie(g, f):
    cx = (f.beak[0] + f.beak[2]) // 2
    stamp(g, cx - 3, f.beak[3] + 1, ["RR...RR", "RRRKRRR", "RR...RR"], {"R": "red", "K": "knot"},
          only=("belly", "body", "shade"))


def sparkle(g, f):
    stamp(g, f.head[1] + 4, 2, [".S.", "SSS", ".S."], {"S": "snow"}, only=(None,))


def pumpkin(g, f):
    shape = ["..L..", ".OOO.", "OOOOO"]
    spot = free_spot(g, shape, range(f.w - 5, f.w // 2, -1), range(f.h - 3, f.h - 8, -1))
    if spot:
        stamp(g, *spot, shape, {"L": "leaf", "O": "orange"})


def santa(g, f):
    x0, x1 = f.head
    cx = (x0 + x1) // 2
    for y, half in ((0, 2), (1, 3)):
        for x in range(cx - half, cx + half + 1):
            put(g, x, y, "red", only=("shade", "body"))
    put(g, cx + 3, 0, "snow", only=(None, "shade"))  # the bobble
    for x in range(cx - 4, cx + 5):  # the white trim
        put(g, x, 2, "snow", only=("shade", "body"))


VARIANTS = {"wink": wink, "glance": glance, "blush": blush, "heart": heart, "fish": fish, "snow": snow,
            "coffee": coffee, "bowtie": bowtie, "sparkle": sparkle, "10-pumpkin": pumpkin, "12-santa": santa}


def main(out=os.path.expanduser("~/.config/fastfetch/tux")):
    base = t2a.build_grid(os.path.join(HERE, "..", "originals", "Tux.svg"), 18, 1.3)
    f = Features(base)
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "plain.ansi"), "w") as fh:
        fh.write(t2a.render(base, PALETTE))
    for name, fn in VARIANTS.items():
        g = copy.deepcopy(base)
        fn(g, f)
        with open(os.path.join(out, name + ".ansi"), "w") as fh:
            fh.write(t2a.render(g, PALETTE))
    print(f"wrote plain + {len(VARIANTS)} variants to {out}")


if __name__ == "__main__":
    main(*sys.argv[1:2])
