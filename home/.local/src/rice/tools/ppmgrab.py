# Read a PPM stream on stdin, save frames at the given fractions of the total (needs --expect N) or last frame.
import sys
from PIL import Image
out, W, H = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
picks = [int(x) for x in sys.argv[4:]]  # frame numbers to keep; last frame always kept
size = W * H * 3
inp = sys.stdin.buffer
n = 0; last = None
while True:
    hdr = b""
    while hdr.count(b"\n") < 2 or not hdr.endswith(b"\n"):
        c = inp.read(1)
        if not c: break
        hdr += c
        if hdr.count(b"\n") == 2 and hdr.endswith(b"\n"):
            # header is "P6\nW H 255\n"
            break
    if not hdr: break
    data = inp.read(size)
    if len(data) < size: break
    last = data
    if n in picks:
        Image.frombytes("RGB", (W, H), data).save(f"{out}_{n}.png")
    n += 1
if last: Image.frombytes("RGB", (W, H), last).save(f"{out}_last.png")
print(n, "frames", file=sys.stderr)
