"""Generate the Android green-robot launcher icon.

Produces:
  res/mipmap-<density>/ic_launcher.png            legacy square icon
  res/mipmap-<density>/ic_launcher_foreground.png adaptive foreground layer

Run:  <venv python> tool/make_launcher_icon.py
Requires Pillow. Geometry is authored in a 108x108 canvas (adaptive-icon dp space).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"

BACKGROUND = (14, 16, 19, 255)  # app background, used behind the robot
ROBOT = (61, 220, 132, 255)  # Android green
SUPERSAMPLE = 8

DENSITIES = {
    "mdpi": 1.0,
    "hdpi": 1.5,
    "xhdpi": 2.0,
    "xxhdpi": 3.0,
    "xxxhdpi": 4.0,
}

# Legacy icon edge in dp, adaptive layer is always 108dp.
LEGACY_DP = 48.0
ADAPTIVE_DP = 108.0


def draw_robot(draw: ImageDraw.ImageDraw, scale: float, cx: float, cy: float, k: float) -> None:
    """Draw the robot centred at (cx, cy); `k` scales the 56x60 blueprint."""
    def xy(x: float, y: float) -> tuple[float, float]:
        return (cx + x * k * scale, cy + y * k * scale)

    def box(x0: float, y0: float, x1: float, y1: float) -> list[float]:
        a = xy(x0, y0)
        b = xy(x1, y1)
        return [a[0], a[1], b[0], b[1]]

    stroke = max(1, round(2.4 * k * scale))

    # Antennae (behind the head).
    draw.line([xy(-12.0, -14.0), xy(-17.0, -21.0)], fill=ROBOT, width=stroke)
    draw.line([xy(12.0, -14.0), xy(17.0, -21.0)], fill=ROBOT, width=stroke)

    # Head: flat-bottomed semicircle (PIL chord sits at the box centre, so the
    # box is twice as tall as the visible head).
    head = box(-20.0, -21.0, 20.0, 29.0)
    draw.pieslice(head, 180, 360, fill=ROBOT)

    # Eyes punched out with the background colour.
    eye_r = 2.8 * k * scale
    for ex in (-8.0, 8.0):
        px, py = xy(ex, -9.0)
        draw.ellipse([px - eye_r, py - eye_r, px + eye_r, py + eye_r], fill=BACKGROUND)

    # Body, arms, legs.
    draw.rounded_rectangle(box(-18.0, 9.0, 18.0, 30.0), radius=2.6 * k * scale, fill=ROBOT)
    draw.rounded_rectangle(box(-25.0, 9.0, -19.0, 27.0), radius=2.4 * k * scale, fill=ROBOT)
    draw.rounded_rectangle(box(19.0, 9.0, 25.0, 27.0), radius=2.4 * k * scale, fill=ROBOT)
    draw.rounded_rectangle(box(-13.0, 33.0, -5.0, 39.0), radius=2.2 * k * scale, fill=ROBOT)
    draw.rounded_rectangle(box(5.0, 33.0, 13.0, 39.0), radius=2.2 * k * scale, fill=ROBOT)


def render(dp: float, density: float, robot_ratio: float) -> Image.Image:
    size = round(dp * density)
    big = size * SUPERSAMPLE
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, big, big], fill=BACKGROUND)
    # Blueprint spans y -21..39, so its centre is 9 units below the origin.
    k = (big * robot_ratio) / 60.0
    draw_robot(draw, 1.0, big / 2.0, big / 2.0 - 9.0 * k, k)
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    for name, density in DENSITIES.items():
        out = RES / f"mipmap-{name}"
        out.mkdir(parents=True, exist_ok=True)
        legacy = render(LEGACY_DP, density, 0.66)
        legacy.save(out / "ic_launcher.png", "PNG", optimize=True)
        adaptive = render(ADAPTIVE_DP, density, 0.52)
        adaptive.save(out / "ic_launcher_foreground.png", "PNG", optimize=True)
        print(f"{name}: ic_launcher {legacy.size[0]}px, foreground {adaptive.size[0]}px")


if __name__ == "__main__":
    main()
