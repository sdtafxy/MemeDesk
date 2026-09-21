#!/usr/bin/env python3
"""从照片生成「基米」菜单栏图标的**四级灰度**数据。

为什么要这么做（而不是手画形状）：
用户的原话是"写实风，可以适当损失细节，但要看起来跟原来差不多"。实测下来，
把照片压成**四级灰度**（暗处 = 实心、亮处 = 透明）在 36px 下仍能认出是这只猫 ——
因为脸的结构本来就靠明暗表达；而"实心剪影 + 挖掉暗部"会把同一份信息变成一摊
不成形的乱白（照片里的暗部是连绵的阴影，不是干净的"眼睛和嘴"）。

产出：Sources/MemeDesk/UI/MenuBarIconBitmaps.swift
  —— 4 级 alpha 按 2bit/像素打包再 base64，54×54 一个图标约 1KB。
  这样 App 里**不需要额外的图片资源**，文件也仍然只依赖 AppKit、能单独编译校对。

用法：
  python3 Scripts/make_menubar_icons.py <咧嘴笑的照片> <挠头的照片>
"""
import base64
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

SIDE = 54          # 3x of 18pt，菜单栏用 36px、设置页预览用 52px，都能覆盖
LEVELS = 4
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Sources" / "MemeDesk" / "UI" / "MenuBarIconBitmaps.swift"

# 取景：主体高度的前百分之多少。再往下就全是胸口了。
CROPS = {"jimiSmile": 0.94, "jimiFacepalm": 0.97}


def subject(path: Path, crop: float):
    """剥背景、裁到头部。

    主体判定**不能**只看暖色：猫的口鼻和胸口是白毛，颜色中性，会被判成背景、
    在剪影里掏出一堆洞（第一版就是这样）。正确做法是从**画面边界洪泛**出真正的背景。
    """
    im = Image.open(path).convert("RGB")
    a = np.asarray(im).astype(float)
    lum = np.asarray(im.convert("L")).astype(float)
    h, w = lum.shape
    k = max(8, min(h, w) // 12)
    corners = np.concatenate([lum[:k, :k].ravel(), lum[:k, -k:].ravel(),
                              lum[-k:, :k].ravel(), lum[-k:, -k:].ravel()])
    bg = float(np.median(corners))
    lb = np.asarray(Image.fromarray(lum.astype(np.uint8))
                    .filter(ImageFilter.GaussianBlur(3))).astype(float)

    cand = ((a[..., 0] - a[..., 2]) < 26) & (lb > bg - 42)     # 又亮又中性 = 候选背景
    is_bg = np.zeros_like(cand)
    q = deque()
    for y in range(h):
        for x in (0, w - 1):
            if cand[y, x] and not is_bg[y, x]:
                is_bg[y, x] = True
                q.append((y, x))
    for x in range(w):
        for y in (0, h - 1):
            if cand[y, x] and not is_bg[y, x]:
                is_bg[y, x] = True
                q.append((y, x))
    while q:
        cy, cx = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = cy + dy, cx + dx
            if 0 <= ny < h and 0 <= nx < w and cand[ny, nx] and not is_bg[ny, nx]:
                is_bg[ny, nx] = True
                q.append((ny, nx))

    mask = ~is_bg
    b = 4                                   # 画面边缘的暗角会挂到主体上，抹掉
    mask[:b, :] = False
    mask[-b:, :] = False
    mask[:, :b] = False
    mask[:, -b:] = False

    ys, xs = np.nonzero(mask)
    x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    cut = int(y0 + (y1 - y0 + 1) * crop)
    return mask[:cut, x0:x1 + 1], lum[:cut, x0:x1 + 1]


def quantize(mask, lum, side: int) -> np.ndarray:
    """四级灰度 → alpha 等级 0..3（暗 = 3）。"""
    ys, xs = np.nonzero(mask)
    x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    bw, bh = x1 - x0 + 1, y1 - y0 + 1

    def fit(arr):
        sub = arr[y0:y1 + 1, x0:x1 + 1].astype(np.float32)
        # 掩膜是 0/1、亮度已经是 0-255 —— 只有前者才需要放大到 0-255。
        # （第一版对亮度也乘了 255，clip 之后整张图变成纯白，四级占比 100% 落在最低级。）
        if float(sub.max()) <= 1.0001:
            sub = sub * 255.0
        img = Image.fromarray(np.clip(sub, 0, 255).astype(np.uint8))
        tw = max(1, int(round(bw * side / max(bw, bh))))
        th = max(1, int(round(bh * side / max(bw, bh))))
        if tw > side:
            tw = side
            th = max(1, int(round(bh * side / bw)))
        if th > side:
            th = side
            tw = max(1, int(round(bw * side / bh)))
        tile = Image.new("L", (side, side), 0)
        resized = img.resize((tw, th), Image.LANCZOS)
        tile.paste(resized, ((side - tw) // 2, (side - th) // 2))
        return np.asarray(tile).astype(float)

    m = fit(mask) > 127.0
    vals = lum[y0:y1 + 1, x0:x1 + 1][mask[y0:y1 + 1, x0:x1 + 1]]
    lo, hi = np.percentile(vals, 6), np.percentile(vals, 94)
    t = np.clip((fit(lum) - lo) / max(1e-6, hi - lo), 0, 1)

    lvl = np.round((1.0 - t) * (LEVELS - 1))       # 暗 = 高等级
    lvl = np.where(m, lvl, 0).astype(np.uint8)
    return lvl


def pack(levels: np.ndarray) -> str:
    """4 级 → 2bit/像素，4 个像素一字节（高位在前），再 base64。"""
    flat = levels.reshape(-1)
    out = bytearray()
    for i in range(0, len(flat), 4):
        chunk = flat[i:i + 4]
        byte = 0
        for j, v in enumerate(chunk):
            byte |= (int(v) & 0b11) << (6 - j * 2)
        out.append(byte)
    return base64.b64encode(bytes(out)).decode("ascii")


def swift_literal(name: str, b64: str) -> str:
    """Swift 多行字符串字面量。

    ⚠️ 不要把 `"..." +` 的拼接语法写进来 —— 那会变成字符串**内容**的一部分，
    解出来就是垃圾（第一版就是这样，图标退化成纯圆盘）。多行字面量里的换行
    由 `Data(base64Encoded:options:.ignoreUnknownCharacters)` 负责忽略。
    """
    lines = [b64[i:i + 100] for i in range(0, len(b64), 100)]
    body = "\n".join("        " + ln for ln in lines)
    return ('    /// %s：%d×%d，4 级 alpha 打包成 2bit/像素\n'
            '    static let %s = """\n%s\n        """\n' % (name, SIDE, SIDE, name, body))


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2

    pieces = []
    for name, arg in zip(CROPS, sys.argv[1:]):
        mask, lum = subject(Path(arg), CROPS[name])
        levels = quantize(mask, lum, SIDE)
        b64 = pack(levels)
        hist = np.bincount(levels.reshape(-1), minlength=LEVELS)
        print(f"{name}: 四级占比 {[f'{h*100//levels.size}%' for h in hist]}  base64 {len(b64)} 字符")
        pieces.append(swift_literal(name, b64))

    OUT.write_text(
        "import AppKit\n\n"
        "// 由 `Scripts/make_menubar_icons.py` 从用户提供的照片生成，**不要手改**。\n"
        "// 四级灰度（暗处 = 实心、亮处 = 透明）按 2bit/像素打包成 base64：\n"
        "// 为什么不用图片资源 —— 这样 App 里不多一份资源，本文件也仍然只依赖 AppKit，\n"
        "// 能像 MenuBarIcon.swift 一样单独 swiftc 出来 dump 成 PNG 做目视校对。\n"
        "enum MenuBarIconBitmaps {\n"
        "    static let side = %d\n\n%s}\n" % (SIDE, "\n".join(pieces))
    )
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
