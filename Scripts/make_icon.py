#!/usr/bin/env python3
"""生成 MemeDesk 的 App 图标。

产出两份：
  Resources/AppIcon.icns   —— 打进 .app，作为 Finder / Dock / 菜单栏的图标
  Resources/AppIcon.png    —— 打进 bundle 的 Resources，程序内（欢迎页、菜单栏面板…）直接读

依赖 Pillow；有 numpy 时用它算渐变（更快），没有也能跑。

用法： python3 Scripts/make_icon.py
"""
import os
import struct

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ICNS = os.path.join(ROOT, "Resources", "AppIcon.icns")
OUT_PNG = os.path.join(ROOT, "Resources", "AppIcon.png")

BASE = 1024
INSET = 74          # 方形留白：macOS 图标不会顶到画布边缘
SUPER = 4.6         # 超椭圆指数，越大越接近圆角矩形

# 对角渐变（暖黄 -> 亮橙 -> 西瓜粉）：足够鲜活，也和「meme」的情绪对得上
STOPS = [
    (255, 219, 92),
    (255, 143, 46),
    (255, 92, 108),
]
# 五官颜色（深棕，比纯黑柔和）
FACE = (72, 42, 14)


def squircle_mask(size: int, inset: int, n: float) -> Image.Image:
    """macOS 风格的连续曲率圆角方形遮罩（扫描线填充，不依赖 numpy）。"""
    span = size - 2 * inset
    radius = span / 2.0
    inside = Image.new("L", (span, span), 0)
    draw = ImageDraw.Draw(inside)

    for y in range(span):
        ty = (y + 0.5 - radius) / radius
        if abs(ty) >= 1.0:
            continue
        half = radius * (1.0 - abs(ty) ** n) ** (1.0 / n)
        draw.line([(radius - half, y), (radius + half, y)], fill=255)

    mask = Image.new("L", (size, size), 0)
    mask.paste(inside, (inset, inset))
    # 1px 羽化，边缘不会有锯齿
    return mask.filter(ImageFilter.GaussianBlur(0.9))


def diagonal_gradient(size: int, stops) -> Image.Image:
    """左上到右下的多段线性渐变。"""
    try:
        import numpy as np
    except ImportError:
        np = None

    if np is not None:
        axis = np.linspace(0.0, 1.0, size, dtype=np.float64)
        t = (axis.reshape(size, 1) + axis.reshape(1, size)) / 2.0
        t = np.clip(t, 0.0, 1.0) * (len(stops) - 1)
        idx = np.clip(t.astype(int), 0, len(stops) - 2)
        frac = (t - idx).astype(np.float64)[..., None]
        lo = np.array(stops, dtype=np.float64)[idx]                    # (size, size, 3)
        hi = np.array(stops, dtype=np.float64)[idx + 1]
        rgb = np.clip(lo + (hi - lo) * frac, 0, 255).astype(np.uint8)
        alpha = np.full((size, size, 1), 255, dtype=np.uint8)
        return Image.fromarray(np.concatenate([rgb, alpha], axis=2), mode="RGBA")

    # 纯 Pillow 兜底：逐行分段插值
    canvas = Image.new("RGBA", (size, size))
    draw = ImageDraw.Draw(canvas)
    span = max(1, size - 1)
    segments = len(stops) - 1
    steps = 64
    for y in range(size):
        ty = y / span
        prev_x = 0
        for step in range(1, steps + 1):
            x = size * step / steps
            t = min(1.0, max(0.0, (x / span + ty) / 2.0)) * segments
            i = min(segments - 1, int(t))
            f = t - i
            a, b = stops[i], stops[i + 1]
            rgb = tuple(int(round(a[c] + (b[c] - a[c]) * f)) for c in range(3))
            draw.line([(prev_x, y), (x, y)], fill=rgb + (255,))
            prev_x = x
    return canvas


def draw_face(canvas: Image.Image) -> None:
    s = canvas.width
    d = ImageDraw.Draw(canvas)

    # 眼睛：两个竖椭圆，间距与大小按画布比例
    eye_w = s * 0.090
    eye_h = s * 0.130
    eye_y = s * 0.412
    for cx in (s * 0.362, s * 0.638):
        d.ellipse([cx - eye_w / 2, eye_y - eye_h / 2, cx + eye_w / 2, eye_y + eye_h / 2], fill=FACE)

    # 嘴：下缘圆弧，圆头端点，笑得很开
    mouth_w = s * 0.46
    mouth_h = s * 0.30
    box = [s / 2 - mouth_w / 2, s * 0.505, s / 2 + mouth_w / 2, s * 0.505 + mouth_h]
    d.arc(box, start=16, end=164, fill=FACE, width=int(s * 0.055))


def add_top_light(canvas: Image.Image) -> None:
    """顶部一道极淡的高光，让平面色块有一点体积感。"""
    s = canvas.width
    fade_to = int(s * 0.52)
    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    for y in range(fade_to):
        alpha = int((1.0 - y / fade_to) * 38)
        draw.line([(0, y), (s, y)], fill=(255, 255, 255, alpha))
    canvas.alpha_composite(glow)


def add_inner_stroke(canvas: Image.Image, mask: Image.Image) -> None:
    """沿轮廓内侧描一圈半透明白边，图标在深浅壁纸上都不会糊掉。"""
    ring = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(5)))
    stroke = Image.new("RGBA", canvas.size, (255, 255, 255, 0))
    stroke.putalpha(Image.eval(ring, lambda v: int(v * 0.55)))
    canvas.alpha_composite(stroke)


def render(size: int) -> Image.Image:
    if size != BASE:
        return render(BASE).resize((size, size), Image.LANCZOS)

    canvas = diagonal_gradient(size, STOPS)
    add_top_light(canvas)
    draw_face(canvas)
    mask = squircle_mask(size, INSET, SUPER)
    add_inner_stroke(canvas, mask)
    canvas.putalpha(mask)
    return canvas


# ICNS 条目：类型 -> 像素边长
ENTRIES = [
    (b"icp4", 16),
    (b"icp5", 32),
    (b"icp6", 64),
    (b"ic07", 128),
    (b"ic08", 256),
    (b"ic09", 512),
    (b"ic10", 1024),
    (b"ic11", 32),    # 16pt @2x
    (b"ic12", 64),    # 32pt @2x
]


def png_bytes(size: int) -> bytes:
    import io

    buf = io.BytesIO()
    render(size).save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def build_icns(path: str) -> None:
    chunks = []
    for kind, size in ENTRIES:
        payload = png_bytes(size)
        chunks.append(kind + struct.pack(">I", len(payload) + 8) + payload)

    body = b"".join(chunks)
    data = b"icns" + struct.pack(">I", len(body) + 8) + body
    with open(path, "wb") as handle:
        handle.write(data)
    print(f"AppIcon.icns  {len(data) / 1024:6.1f} KB  ({len(ENTRIES)} sizes, {BASE}px master)")


def build_png(path: str) -> None:
    render(512).save(path, format="PNG", optimize=True)
    print(f"AppIcon.png   {os.path.getsize(path) / 1024:6.1f} KB  (512px, used inside the app)")


if __name__ == "__main__":
    os.makedirs(os.path.dirname(OUT_ICNS), exist_ok=True)
    build_icns(OUT_ICNS)
    build_png(OUT_PNG)
    print("wrote Resources/AppIcon.icns, Resources/AppIcon.png")
