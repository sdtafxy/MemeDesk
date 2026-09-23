#!/usr/bin/env python3
"""从照片生成「基米」菜单栏图标的数据。

**做法：色调映射（写实风），照片里亮的实心、暗的透明。**

脸整块（照片里偏亮的毛）→ 实心；五官（偏黑的眼睛 / 鼻 / 嘴）→ 透明。
这保留了照片本身的明暗结构（毛色的深浅、轮廓的起伏），所以 18pt 下仍认得出是这只猫
—— 这比"二值剪影 + 抠掉五官"更接近用户说的"写实风，可以适当损失细节，但要看起来跟原来差不多"。

⚠️ **极性**：0.1.5 那版是 `lvl = round((1-t)*3)`（暗 = 实心），于是**最亮的脸落到 0 级**、
整只猫摊在 1 级（alpha 85）上 —— 观感"太淡、猫咪脸部都空心了"。
反成 `round(t*3)` 之后才对。

⚠️ **光反极性还不够**：照片里的"脸"是一大片中间调，直接反照旧会有一半落在 1/2 级
（半透明灰），看着还是不实。所以要再压一道**色阶**（`TONE_BLACK` / `TONE_WHITE`）：
抬黑场让五官真的透明、压白场让**中间调的脸也吃成实心**。这两个数只有 18pt 下才看得出差别。

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

# 主体最长的那个方向占画布的比例。
#
# ⚠️ 不能铺满 100%：8 个矢量脸的圆盘直径是 24 格网格里的 20.6 ≈ **86%**，
# 照片量化出来的这两只是**贴满画布**的（实测宽 100%、高 93%），
# 于是它们在同一排里明显比别的图标大一圈、重一档，破掉了设计语言的统一。
# 对齐到 86% 之后，一组十只的视觉重量才一致。
FILL = 0.86

# 色阶（压在"按主体 6%/94% 分位归一化"之后的一道上限/下限裁剪）。
#   t 是归一化亮度：0 = 照片里最暗，1 = 最亮。
#   · 抬黑场 → 比 TONE_BLACK 还暗的（五官）直接透明；
#   · 压白场 → 比 TONE_WHITE 还亮的（脸）直接实心，**这就是"脸部要更实"**。
# 调这俩时一定按 18pt 看（放大看反而看不出差别）。
TONE_BLACK = 0.18
TONE_WHITE = 0.55
TONE_GAMMA = 1.0     # 中间调再额外抬一档（<1 更实），1.0 = 不抬

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
    # ⚠️ 一个主体像素都没有时，`np.nonzero` 给的是空数组，`.min()` 会抛一个
    # 完全读不出缘由的 `ValueError: zero-size array to reduction operation minimum`。
    # 触发条件是"四条边一个背景种子都播不到"（整幅图都被判成候选背景）——
    # 真实的猫照片不会，但换素材时值得给人一句人话。
    if ys.size == 0:
        raise SystemExit(
            f"error: 在 {path} 里找不到主体 —— 剥背景后整幅图都被判成了背景。\n"
            "       换一张主体与背景反差更大的照片，或调 subject() 里候选背景的判据。")
    x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    cut = int(y0 + (y1 - y0 + 1) * crop)
    return mask[:cut, x0:x1 + 1], lum[:cut, x0:x1 + 1]


def quantize(mask, lum, side: int) -> np.ndarray:
    """照片 → alpha 等级 0..3。见模块开头：**亮 = 实心、暗 = 透明** + 一道色阶。"""
    ys, xs = np.nonzero(mask)
    x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    bw, bh = x1 - x0 + 1, y1 - y0 + 1

    def place(arr):
        """把主体包围盒裁出来、按 FILL 缩放进 side×side 的画布居中。"""
        sub = arr[y0:y1 + 1, x0:x1 + 1].astype(np.float32)
        # 掩膜是 0/1、亮度已经是 0-255 —— 只有前者才需要放大到 0-255。
        if float(sub.max()) <= 1.0001:
            sub = sub * 255.0
        img = Image.fromarray(np.clip(sub, 0, 255).astype(np.uint8))
        target = side * FILL
        tw = max(1, int(round(bw * target / max(bw, bh))))
        th = max(1, int(round(bh * target / max(bw, bh))))
        if tw > side:
            tw = side
            th = max(1, int(round(bh * target / bw)))
        if th > side:
            th = side
            tw = max(1, int(round(bw * target / bh)))
        tile = Image.new("L", (side, side), 0)
        tile.paste(img.resize((tw, th), Image.LANCZOS), ((side - tw) // 2, (side - th) // 2))
        return np.asarray(tile).astype(float)

    # 分位只统计**主体内部**的像素，否则背景的亮/暗会把动态范围带偏。
    vals = lum[y0:y1 + 1, x0:x1 + 1][mask[y0:y1 + 1, x0:x1 + 1]]
    lo, hi = np.percentile(vals, 6), np.percentile(vals, 94)
    t = np.clip((place(lum) - lo) / max(1e-6, hi - lo), 0.0, 1.0)

    # 色阶：t 越接近 1（照片里越亮）→ 等级越高（越实心）。
    t = np.clip((t - TONE_BLACK) / max(1e-6, TONE_WHITE - TONE_BLACK), 0.0, 1.0) ** TONE_GAMMA

    # 乘主体**软边**（而不是硬掩膜）→ 轮廓自带抗锯齿，不会有一圈锯齿。
    alpha = t * (place(mask.astype(float)) / 255.0)
    return np.round(alpha * (LEVELS - 1)).astype(np.uint8)


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
        "// 4 级 alpha（照片里亮的脸 = 实心、暗的五官 = 透明）按 2bit/像素打包成 base64：\n"
        "// 为什么不用图片资源 —— 这样 App 里不多一份资源，本文件也仍然只依赖 AppKit，\n"
        "// 能像 MenuBarIcon.swift 一样单独 swiftc 出来 dump 成 PNG 做目视校对。\n"
        "enum MenuBarIconBitmaps {\n"
        "    static let side = %d\n\n%s}\n" % (SIDE, "\n".join(pieces))
    )
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
