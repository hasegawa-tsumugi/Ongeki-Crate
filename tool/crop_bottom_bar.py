"""Crop the bottom bar out of build/shots/bottom-bar-*.png and zoom it 2x.

Only used to eyeball the glass: the full-page shots are too small to tell a
2dp blur from an 8dp one.

Usage: python tool/crop_bottom_bar.py
Out:   build/shots/zoom-<name>.png
"""

from __future__ import annotations

import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHOTS = ROOT / "build" / "shots"

# Logical geometry of the bar, mirrored from lib/src/bottom_bar.dart:
#   height 64, bottom max(min(w*.0604, h*.10), safe + 8), inset w*.106
# The shots are taken at pixelRatio 2 from a 390x900 (or 320x720) view, with
# viewPadding.bottom == 0 under the test harness.
def bar_rect(width: int, height: int) -> tuple[int, int, int, int]:
    """Return (left, top, right, bottom) in *shot* pixels."""
    w, h = width / 2, height / 2  # back to logical
    inset = min(max(w * 0.106, 16.0), 56.0)
    bottom = max(min(w * 0.0604, h * 0.10), 8.0)
    top = h - bottom - 64
    pad = 14  # a little air so the press shadow is not cut off
    return (
        int((inset - pad) * 2),
        int((top - pad) * 2),
        int((w - inset + pad) * 2),
        int((h - bottom + pad) * 2),
    )


def main(names: list[str]) -> int:
    if not names:
        names = [p.name for p in sorted(SHOTS.glob("bottom-bar-*.png"))]
    for name in names:
        src = SHOTS / name
        if not src.exists():
            print(f"missing: {src}")
            return 1
        image = Image.open(src).convert("RGBA")
        crop = image.crop(bar_rect(*image.size))
        zoom = crop.resize((crop.width * 2, crop.height * 2), Image.NEAREST)
        out = SHOTS / f"zoom-{name}"
        zoom.save(out)
        print(f"{out.name}  {zoom.width}x{zoom.height}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
