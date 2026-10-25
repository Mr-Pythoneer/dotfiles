import json, os, subprocess, sys, shutil
from PIL import Image
T = os.path.dirname(os.path.abspath(__file__)); W = os.path.join(T, "..", "walls")
OUT = os.path.join(T, "preview"); FULL = os.path.join(T, "full"); os.makedirs(OUT, exist_ok=True); os.makedirs(FULL, exist_ok=True)
P = {
 "onedark":  dict(bg="#282c34", bg2="#21252b", bg3="#3e4451", fg="#abb2bf", muted="#5c6370", accent="#61afef", accent2="#c678dd", str="#98c379", cycle=["#e06c75","#d19a66","#e5c07b","#98c379","#56b6c2","#61afef","#c678dd"]),
 "dracula":  dict(bg="#282a36", bg2="#1e1f29", bg3="#44475a", fg="#f8f8f2", muted="#6272a4", accent="#bd93f9", accent2="#ff79c6", str="#f1fa8c", cycle=["#ff5555","#ffb86c","#f1fa8c","#50fa7b","#8be9fd","#bd93f9","#ff79c6"]),
 "gruvbox":  dict(bg="#282828", bg2="#1d2021", bg3="#3c3836", fg="#ebdbb2", muted="#928374", accent="#fabd2f", accent2="#fe8019", str="#b8bb26", cycle=["#fb4934","#fe8019","#fabd2f","#b8bb26","#8ec07c","#83a598","#d3869b"]),
 "monokai":  dict(bg="#2d2a2e", bg2="#221f22", bg3="#403e41", fg="#fcfcfa", muted="#727072", accent="#ffd866", accent2="#ff6188", str="#a9dc76", cycle=["#ff6188","#fc9867","#ffd866","#a9dc76","#78dce8","#ab9df2"]),
 "github":   dict(bg="#0d1117", bg2="#010409", bg3="#21262d", fg="#e6edf3", muted="#7d8590", accent="#58a6ff", accent2="#bc8cff", str="#a5d6ff", cycle=["#ff7b72","#ffa657","#e3b341","#3fb950","#39c5cf","#58a6ff","#bc8cff"]),
 "solarized":dict(bg="#002b36", bg2="#00212b", bg3="#073642", fg="#93a1a1", muted="#586e75", accent="#268bd2", accent2="#2aa198", str="#859900", cycle=["#dc322f","#cb4b16","#b58900","#859900","#2aa198","#268bd2","#6c71c4","#d33682"]),
 "nord":     dict(bg="#2e3440", bg2="#242933", bg3="#3b4252", fg="#d8dee9", muted="#616e88", accent="#88c0d0", accent2="#b48ead", str="#a3be8c", cycle=["#bf616a","#d08770","#ebcb8b","#a3be8c","#8fbcbb","#81a1c1","#b48ead"]),
 "phosphor": dict(bg="#0c120d", bg2="#060a07", bg3="#16261b", fg="#b4f8c4", muted="#4a7a57", accent="#39ff88", accent2="#ffb000", str="#7dffb0", cycle=["#39ff88","#7dffb0","#ffb000","#ffd27a","#5fffd7","#b8ff5f"]),
}
LUT_SRC = {
 "git-live":   os.path.join(T, "repos/gource_b_380.png"),
 "git-still":  os.path.join(T, "repos/gource_b_last.png"),
 "source-a":   os.path.join(W, "dl3/unsplash_OqtafYT5kTw.jpg"),
 "source-b":   os.path.join(W, "dl3/unsplash_ieic5Tq8YMk.jpg"),
 "circuit-a":  os.path.join(W, "dl/41_misc.png"),
 "circuit-b":  os.path.join(W, "dl/26_nord.png"),
 "ascii-a":    os.path.join(W, "dl3/ascii_arch_1.png"),
 "rain-b":     os.path.join(W, "dl3/unsplash_iar-afB0QQw.jpg"),
}
def rgb01(h, k=1.0): return ",".join(f"{int(h[i:i+2],16)/255*k:.3f}" for i in (1,3,5))
def mix(a, b, t): return "#" + "".join(f"{round(int(a[i:i+2],16)+(int(b[i:i+2],16)-int(a[i:i+2],16))*t):02x}" for i in (1,3,5))
def cover(src, dst, w, h, q=82):
    im = Image.open(src).convert("RGB"); s = max(w/im.width, h/im.height)
    im = im.resize((round(im.width*s), round(im.height*s)), Image.LANCZOS)
    l, t = (im.width-w)//2, (im.height-h)//2
    im.crop((l, t, l+w, t+h)).save(dst, quality=q)

# normalised 1920-wide copies of the lutgen sources
os.makedirs(os.path.join(T, "src"), exist_ok=True)
for k, f in LUT_SRC.items():
    d = os.path.join(T, "src", k + ".png")
    if not os.path.exists(d):
        im = Image.open(f).convert("RGB"); im.thumbnail((1920, 1920)); im.save(d)

for pid, p in P.items():
    colors = list(dict.fromkeys([p["bg2"], p["bg"], p["bg3"], p["fg"], p["muted"], p["accent"], p["accent2"]] + p["cycle"]))
    for k in LUT_SRC:
        full = os.path.join(FULL, f"{k}-{pid}.png")
        subprocess.run([os.path.join(T, "bin/lutgen"), "apply", "-o", full, os.path.join(T, "src", k + ".png"), "--", *colors], check=True, capture_output=True)
        cover(full, os.path.join(OUT, f"{k}-{pid}.jpg"), 960, 600)
    # code rain, rendered by Rezmason/matrix in this palette
    base = mix(p["bg2"], "#000000", .35)
    pal = ",".join([rgb01(base), "0", rgb01(p["accent"], .35), "0.25", rgb01(p["accent"]), "0.6", rgb01(mix(p["accent"], "#ffffff", .55)), "1"])
    url = f"http://127.0.0.1:8765/?version=classic&palette={pal}&backgroundColor={rgb01(base)}&cursorColor={rgb01(mix(p['fg'], '#ffffff', .6))}&suppressWarnings=true"
    full = os.path.join(FULL, f"rain-a-{pid}.png")
    subprocess.run(["timeout", "90", "google-chrome-stable", "--headless=new", "--no-sandbox", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
                    "--hide-scrollbars", "--window-size=1920,1200", "--virtual-time-budget=9000", f"--screenshot={full}", url], capture_output=True)
    cover(full, os.path.join(OUT, f"rain-a-{pid}.jpg"), 960, 600)
    # your GitHub skyline, rendered in this palette
    q = "&".join(f"{a}={b.lstrip('#')}" for a, b in [("bg", p["bg2"]), ("base", mix(p["bg3"], p["fg"], .12)), ("low", p["str"]), ("high", p["accent"]), ("top", p["accent2"]), ("rim", p["accent2"])])
    name = f"skyline-a-{pid}.png"; full = os.path.join(T, "sky/out", name)
    r = subprocess.run([os.path.join(T, "render1.sh"), f"http://127.0.0.1:8767/render.html?name={name}&w=1920&h=1200&{q}", full], capture_output=True, text=True)
    shutil.copy(full, os.path.join(FULL, name))
    cover(full, os.path.join(OUT, f"skyline-a-{pid}.jpg"), 960, 600)
    print(pid, "done", r.stdout.strip(), flush=True)
