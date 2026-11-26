"""Fill the placeholder block in the fullscreen-jacket shot with a mock cover.

The jacket image is fetched from the network, so under `flutter test` the
fullscreen page renders the grey placeholder. This script replaces that
block with a gradient so the page layout can be judged; it is a mock and is
written to a separate file so it never passes for a real screenshot.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

SHOTS = Path("build/shots")
SRC = SHOTS / "jacket-fullscreen.png"
DST = SHOTS / "jacket-fullscreen-illustrated.png"

# 播放器占位块的底色（_Jacket._placeholder 的 0xFF353535）。
PLACEHOLDER = (53, 53, 53)


def find_block(img):
    w, h = img.size
    px = img.load()
    xs, ys = [], []
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            r, g, b = px[x, y][:3]
            if abs(r - PLACEHOLDER[0]) < 4 and abs(g - PLACEHOLDER[1]) < 4 and abs(b - PLACEHOLDER[2]) < 4:
                xs.append(x)
                ys.append(y)
    if not xs:
        raise SystemExit("no placeholder block found")
    return min(xs), min(ys), max(xs), max(ys)


def gradient(size, top, bottom, corner):
    w, h = size
    img = Image.new("RGB", (w, h), top)
    draw = ImageDraw.Draw(img)
    for i in range(h):
        t = i / max(1, h - 1)
        c = tuple(round(top[k] + (bottom[k] - top[k]) * t) for k in range(3))
        draw.line([(0, i), (w, i)], fill=c)
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.ellipse([w * 0.62, h * 0.06, w * 1.02, h * 0.46], fill=(255, 255, 255, 46))
    od.ellipse([w * 0.02, h * 0.68, w * 0.30, h * 0.96], fill=(255, 255, 255, 34))
    return Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")


def main():
    img = Image.open(SRC).convert("RGB")
    x0, y0, x1, y1 = find_block(img)
    print(f"placeholder block: {x0},{y0} -> {x1},{y1}")
    cover = gradient((x1 - x0 + 1, y1 - y0 + 1), (43, 27, 77), (242, 193, 78), (176, 58, 140))
    img.paste(cover, (x0, y0))
    img.save(DST)
    print(f"wrote {DST} ({DST.stat().st_size} bytes)")


if __name__ == "__main__":
    sys.exit(main())
