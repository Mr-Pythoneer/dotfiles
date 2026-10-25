#!/usr/bin/env python3
"""The Fedora twin of 3-ascii-arch.png for the Fedora VM: Fedora's neofetch ASCII logo (neofetch, MIT,
Dylan Araps; the same family of art as the Arch one), set the same way: JetBrains Mono, ~18 px per
character and 36.5 px per line at 3840x2160, centred on the same navy. The background c's in a pale
blue next to the Arch one's pale cyan, the f in near-white.

    ascii-fedora.py OUT.png
"""
import sys

from PIL import Image, ImageDraw, ImageFont

F_LOGO = r"""
             .',;::::;,'.
         .';:cccccccccccc:;,.
      .;cccccccccccccccccccccc;.
    .:cccccccccccccccccccccccccc:.
  .;ccccccccccccc;.:dddl:.;ccccccc;.
 .:ccccccccccccc;OWMKOOXMWd;ccccccc:.
.:ccccccccccccc;KMMc;cc;xMMc;ccccccc:.
,cccccccccccccc;MMM.;cc;;WW:;cccccccc,
:cccccccccccccc;MMM.;cccccccccccccccc:
:ccccccc;oxOOOo;MMM000k.;cccccccccccc:
cccccc;0MMKxdd:;MMMkddc.;cccccccccccc;
ccccc;XMO';cccc;MMM.;cccccccccccccccc'
ccccc;MMo;ccccc;MMW.;ccccccccccccccc;
ccccc;0MNc.ccc.xMMd;ccccccccccccccc;
cccccc;dNMWXXXWM0:;cccccccccccccc:,
cccccccc;.:odl:.;cccccccccccccc:,.
ccccccccccccccccccccccccccccc:'.
:ccccccccccccccccccccccc:;,..
 ':cccccccccccccccc::;,.
""".strip("\n").splitlines()
F_LOGO_WHITE = [  # 2 = the white f, 1 = the blue background
    "             111111111111",
    "         11111111111111111111",
    "      11111111111111111111111111",
    "    111111111111111111111111111111",
    "  1111111111111111222222221111111111",
    " 111111111111111122222222221111111111",
    "11111111111111112222111122221111111111",
    "11111111111111112222111122221111111111",
    "11111111111111112222111111111111111111",
    "11111111122222212222222211111111111111",
    "11111112222222212222222211111111111111",
    "11111122221111112222111111111111111111",
    "1111112221111111222211111111111111111",
    "111111222221112222211111111111111111",
    "11111112222222222211111111111111111",
    "1111111112222222111111111111111111",
    "11111111111111111111111111111111",
    "11111111111111111111111111111",
    " 11111111111111111111111",
]

BG, BLUE, WHITE = (26, 30, 37), (160, 190, 232), (236, 240, 244)
W, H, PITCH, SIZE = 3840, 2160, 36.5, 30
FONT = "/usr/share/fonts/TTF/JetBrainsMonoNerdFontMono-Regular.ttf"


def main(out):
    font = ImageFont.truetype(FONT, SIZE)
    cw = font.getlength("M")
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    cols = max(map(len, F_LOGO))
    x0 = round((W - cols * cw) / 2)
    y0 = round((H - len(F_LOGO) * PITCH) / 2)
    for i, (line, mask) in enumerate(zip(F_LOGO, F_LOGO_WHITE)):
        for j, ch in enumerate(line):
            if ch != " ":
                d.text((x0 + j * cw, y0 + i * PITCH), ch, font=font, fill=WHITE if mask[j:j + 1] == "2" else BLUE)
    img.save(out)


if __name__ == "__main__":
    main(sys.argv[1])
