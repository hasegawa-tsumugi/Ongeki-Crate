"""液态玻璃折射的离线原型：把 glass.frag 的数学搬到 numpy，验证形状与强度。

不替代真机验证（BackdropFilter 的坐标语义只有 Impeller 能验），只用来先排除
「SDF / 梯度 / 位移方向写错」这一整类问题 —— 这类错在真机上表现为「玻璃歪了」
或「边缘糊成一坨」，很难一眼看出是哪一步错的。

数学与 assets/shader/glass.frag 一致（Kyant0/AndroidLiquidGlass 的
RoundedRectRefractionShaderString 移植）：circleMap 圆弧轮廓 + 解析梯度。
amount = 带高时轮廓在带内折返，背景翻折压缩 —— 那是厚玻璃透镜的边缘质感。

用法：python tool/preview_glass.py
输出：
  build/shots/glass-field.png     位移场（确认折射带只出现在边缘、圆角过渡正确）
  build/shots/glass-prototype.png 合成对比（1:1 放大，确认观感）
"""
import numpy as np
from PIL import Image, ImageDraw

FIELD_OUT = "build/shots/glass-field.png"
PROTO_OUT = "build/shots/glass-prototype.png"

# 与 lib/src/bottom_bar.dart 的常量保持一致。
BLUR = .10
REFR_H = .20
REFR_AMT = .20


def sd_round_rect(px, py, hw, hh, r):
    qx = np.abs(px) - hw + r
    qy = np.abs(py) - hh + r
    return (np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
            + np.minimum(np.maximum(qx, qy), 0) - r)


def circle_map(x):
    """位移轮廓：四分之一圆弧，边缘斜率无穷大。"""
    return 1.0 - np.sqrt(np.maximum(1.0 - x * x, 0.0))


def displacement(w, h, radius_frac, refr_h_pct, refr_amt_pct):
    """返回 (dx, dy, d)：与 shader 完全一致的位移场（朝内采样）。"""
    refr_h = h * refr_h_pct
    amt = h * refr_amt_pct
    ys, xs = np.mgrid[0:h, 0:w]
    px = xs + .5 - w / 2
    py = ys + .5 - h / 2
    hw, hh = w / 2, h / 2
    rad = h * radius_frac

    d = sd_round_rect(px, py, hw, hh, rad)
    # 解析梯度（与 gradSdRoundedRect 同构）：平角边轴向、圆角径向。
    qx = np.abs(px) - hw + rad
    qy = np.abs(py) - hh + rad
    corner = (qx >= 0) | (qy >= 0)
    mx, my = np.maximum(qx, 0), np.maximum(qy, 0)
    ml = np.hypot(mx, my)
    ml_safe = np.where(ml < 1e-6, 1, ml)
    gx_c = np.sign(px) * (mx / ml_safe)
    gy_c = np.sign(py) * (my / ml_safe)
    grad_x = (qy <= qx).astype(np.float32)      # step(qy, qx)
    gx_i = np.sign(px) * grad_x
    gy_i = np.sign(py) * (1 - grad_x)
    nx = np.where(corner, gx_c, gx_i)
    ny = np.where(corner, gy_c, gy_i)

    if refr_h <= 0 or amt <= 0:
        return np.zeros_like(px), np.zeros_like(py), d

    inner = np.minimum(d, 0)
    disp = circle_map(1 - -inner / refr_h) * amt
    band = -d < refr_h
    return -nx * disp * band, -ny * disp * band, d


def bilinear(src, sx, sy):
    h, w = sx.shape
    sx = np.clip(sx, 0, w - 1.001)
    sy = np.clip(sy, 0, h - 1.001)
    ix, iy = sx.astype(int), sy.astype(int)
    fx, fy = (sx - ix)[..., None], (sy - iy)[..., None]
    ix1, iy1 = np.minimum(ix + 1, w - 1), np.minimum(iy + 1, h - 1)
    a, b = src[iy, ix], src[iy, ix1]
    c, e = src[iy1, ix], src[iy1, ix1]
    return (a * (1 - fx) * (1 - fy) + b * fx * (1 - fy)
            + c * (1 - fx) * fy + e * fx * fy)


def make_background(w, h):
    """高对比背景：白网格 + 洋红斜线。折射生效时线会明显弯折。"""
    img = Image.new("RGB", (w, h), (18, 20, 26))
    d = ImageDraw.Draw(img)
    for x in range(0, w, 24):
        d.line([(x, 0), (x, h)], fill=(70, 78, 96), width=1)
    for y in range(0, h, 24):
        d.line([(0, y), (w, y)], fill=(70, 78, 96), width=1)
    d.line([(0, int(h * .62)), (w, int(h * .30))], fill=(226, 96, 172), width=4)
    d.line([(0, int(h * .72)), (w, int(h * .44))], fill=(96, 200, 226), width=3)
    return np.asarray(img).astype(np.float32)


def vibrancy(rgb):
    """饱和 ×1.5，与 shader 里的 vibrancy() 一致。"""
    luma = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    return luma[..., None] + (rgb - luma[..., None]) * 1.5


def glass_layer(w, h, radius_frac, refr_h_pct, refr_amt_pct, tint_rgba):
    """返回 (rgb, alpha)：已裁圆角的玻璃像素。"""
    src = vibrancy(make_background(w, h))
    dx, dy, d = displacement(w, h, radius_frac, refr_h_pct, refr_amt_pct)
    ys, xs = np.mgrid[0:h, 0:w]
    refr = bilinear(src, xs - dx, ys - dy)
    tr, tg, tb, ta = tint_rgba
    rgb = refr * (1 - ta) + np.array([tr, tg, tb], dtype=np.float32) * ta

    mask = np.clip(-d, 0, 1)[..., None]      # 1 = 内部
    return rgb * mask, mask


def compose_over(bg, layer, box):
    x0, y0, x1, y1 = box
    out = bg.copy()
    rgb, alpha = layer
    out[y0:y1, x0:x1] = rgb + out[y0:y1, x0:x1] * (1 - alpha)
    return out


def field_image(w, h):
    dx, dy, d = displacement(w, h, .5, REFR_H, REFR_AMT)
    mag = np.hypot(dx, dy)
    v = np.clip(mag / max(mag.max(), 1e-6), 0, 1)
    # 洋红单色：亮=位移大，黑=不动。折射带应当只在边缘一圈。
    rgb = np.stack([v * 255, v * 90, v * 190], axis=-1)
    return Image.fromarray(rgb.astype(np.uint8)), mag


def main():
    # ── 位移场：三个参数档位并排，确认「带」的范围与圆角贴合 ──
    PW, PH = 560, 96
    cases = [("amt = band (ref default)", REFR_H, REFR_H),
             ("amt = 0.5 band (no fold)", REFR_H, REFR_H * .5),
             ("amt = 2 band", REFR_H, REFR_H * 2)]
    tiles = []
    for name, rh, ra in cases:
        dx, dy, d = displacement(PW, PH, .5, rh, ra)
        mag = np.hypot(dx, dy)
        v = np.clip(mag / max(mag.max(), 1e-6), 0, 1)
        rgb = np.stack([v * 255, v * 90, v * 190], axis=-1)
        tile = Image.fromarray(rgb.astype(np.uint8))
        ImageDraw.Draw(tile).text((10, 8), f"{name}  max {mag.max():.1f}px", fill=(255, 255, 255))
        tiles.append(tile)

    sheet = Image.new("RGB", (PW, (PH + 10) * len(tiles)), (0, 0, 0))
    for i, t in enumerate(tiles):
        sheet.paste(t, (0, i * (PH + 10)))
    sheet.save(FIELD_OUT)
    print("wrote", FIELD_OUT, sheet.size)

    # ── 合成：真实尺寸的胶囊压在背景上，1:1 看观感 ──
    BW, BH = 900, 300
    bg = make_background(BW, BH)
    PW2, PH2 = 620, 96
    box = ((BW - PW2) // 2, (BH - PH2) // 2,
           (BW - PW2) // 2 + PW2, (BH - PH2) // 2 + PH2)

    variants = [("off", 0.0, 0.0),
                ("amt = 0.5 band (fold suppressed)", REFR_H, REFR_H * .5),
                ("amt = band  (ref default / ours)", REFR_H, REFR_H),
                ("amt = 2 band", REFR_H, REFR_H * 2)]
    rows = []
    for name, rh, ra in variants:
        canvas = bg.copy()
        layer = glass_layer(PW2, PH2, .5, rh, ra,
                           (18, 18, 18, .4))  # 深色表面 0xFF121212 @ 40%
        canvas = compose_over(canvas, layer, box)
        img = Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8))
        # 1px 描边，贴近 App 里的前景描边
        ImageDraw.Draw(img).rounded_rectangle(
            [box[0], box[1], box[2] - 1, box[3] - 1],
            radius=PH2 / 2, outline=(255, 255, 255, 60), width=1)
        ImageDraw.Draw(img).text((12, 10), name, fill=(255, 255, 255))
        rows.append(img)

    out = Image.new("RGB", (BW, (BH + 8) * len(rows)), (0, 0, 0))
    for i, img in enumerate(rows):
        out.paste(img, (0, i * (BH + 8)))
    out.save(PROTO_OUT)
    print("wrote", PROTO_OUT, out.size)


if __name__ == "__main__":
    main()
