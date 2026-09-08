#!/usr/bin/env python3
"""生成 MemeDesk 内置的示例素材（5 个 GIF + 1 个 MP4，约 100KB）。

素材刻意做得小而节制：160px 尺寸、调色板压缩、帧数不过度，
打开 App 就能看到效果，又不会把仓库撑大。

用法： python3 Scripts/generate_samples.py
"""
import math
import os
import shutil
import subprocess

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Resources", "Samples")
SIZE = 160
BG = (0, 0, 0, 0)

os.makedirs(OUT, exist_ok=True)


def new_frame():
    img = Image.new("RGBA", (SIZE, SIZE), BG)
    return img, ImageDraw.Draw(img)


def ease(t):
    return 0.5 - 0.5 * math.cos(math.pi * t)


def save(frames, name, duration=90):
    first, rest = frames[0], frames[1:]
    first.save(
        os.path.join(OUT, name),
        save_all=True,
        append_images=rest,
        duration=duration,
        loop=0,
        optimize=True,
        disposal=2,
    )
    path = os.path.join(OUT, name)
    print(f"{name:22s} {os.path.getsize(path) / 1024:6.1f} KB  {len(frames)} frames")


# ---------------------------------------------------------------- 1. 弹跳笑脸
def bobbing_face():
    frames = []
    n = 24
    for i in range(n):
        t = i / n
        img, d = new_frame()
        y = int(46 + abs(math.sin(t * 2 * math.pi)) * -14 + 14)
        body = (SIZE / 2 - 44, y, SIZE / 2 + 44, y + 88)
        d.ellipse(body, fill=(255, 214, 61, 255), outline=(38, 34, 30, 255), width=3)
        eye_y = y + 30
        blink = abs(math.sin(t * 4 * math.pi)) > 0.95
        for ex in (SIZE / 2 - 17, SIZE / 2 + 17):
            if blink:
                d.line((ex - 7, eye_y, ex + 7, eye_y), fill=(38, 34, 30, 255), width=3)
            else:
                d.ellipse((ex - 5, eye_y - 5, ex + 5, eye_y + 5), fill=(38, 34, 30, 255))
        smile = (SIZE / 2 - 18, y + 46, SIZE / 2 + 18, y + 66)
        d.arc(smile, start=15, end=165, fill=(38, 34, 30, 255), width=4)
        # 影子跟着弹起变淡
        sy = 142
        sw = int(38 - abs(math.sin(t * 2 * math.pi)) * 8)
        d.ellipse((SIZE / 2 - sw, sy, SIZE / 2 + sw, sy + 8), fill=(120, 120, 120, 90))
        frames.append(img.convert("P", palette=Image.ADAPTIVE, colors=32))
    return frames


# ---------------------------------------------------------------- 2. 心跳
def heartbeat():
    frames = []
    n = 18
    for i in range(n):
        t = i / n
        img, d = new_frame()
        pulse = 1.0 + 0.22 * (math.sin(t * 4 * math.pi) ** 6)
        w, h = 56 * pulse, 50 * pulse
        cx, cy = SIZE / 2, SIZE / 2
        # 两瓣圆 + 下方尖
        d.ellipse((cx - w, cy - h * 0.9, cx, cy + h * 0.25), fill=(236, 72, 92, 255))
        d.ellipse((cx, cy - h * 0.9, cx + w, cy + h * 0.25), fill=(236, 72, 92, 255))
        d.polygon(
            [(cx - w * 0.92, cy - h * 0.1), (cx + w * 0.92, cy - h * 0.1), (cx, cy + h * 1.15)],
            fill=(236, 72, 92, 255),
        )
        frames.append(img.convert("P", palette=Image.ADAPTIVE, colors=16))
    return frames


# ---------------------------------------------------------------- 3. 吞吐圆环
def spinner():
    frames = []
    n = 20
    for i in range(n):
        img, d = new_frame()
        base = i / n * 2 * math.pi
        for k in range(6):
            ang = base + k * 2 * math.pi / 6
            r = 46
            x = SIZE / 2 + math.cos(ang) * r
            y = SIZE / 2 + math.sin(ang) * r
            rad = 6 + 5 * (k / 5)
            alpha = int(80 + 175 * (k / 5))
            d.ellipse((x - rad, y - rad, x + rad, y + rad), fill=(90, 200, 250, alpha))
        frames.append(img.convert("P", palette=Image.ADAPTIVE, colors=32))
    return frames


# ---------------------------------------------------------------- 4. DVD 弹球
def dvd_bounce():
    frames = []
    n = 32
    palette = [(255, 59, 92), (255, 202, 58), (76, 217, 100), (52, 152, 219), (155, 89, 182), (255, 159, 67)]
    bw, bh = 46, 26
    for i in range(n):
        t = i / n
        x = t * (SIZE - bw)
        y = abs(math.sin(t * math.pi * 2)) * (SIZE - bh)
        img, d = new_frame()
        color = palette[int(t * len(palette)) % len(palette)]
        d.rounded_rectangle((x, y, x + bw, y + bh), radius=6, fill=color + (255,))
        frames.append(img.convert("P", palette=Image.ADAPTIVE, colors=16))
    return frames


# ---------------------------------------------------------------- 5. 摇摆企鹅
def wobble_penguin():
    frames = []
    n = 20
    for i in range(n):
        img, d = new_frame()
        lean = math.sin(i / n * 2 * math.pi) * 0.28
        cx = SIZE / 2
        img_body = Image.new("RGBA", (SIZE, SIZE), BG)
        bd = ImageDraw.Draw(img_body)
        bd.ellipse((cx - 46, 44, cx + 46, 132), fill=(38, 42, 56, 255))
        bd.ellipse((cx - 30, 60, cx + 30, 112), fill=(250, 250, 250, 255))
        bd.ellipse((cx - 14, 50, cx + 14, 78), fill=(250, 250, 250, 255))
        bd.ellipse((cx - 7, 61, cx - 1, 67), fill=(38, 42, 56, 255))
        bd.ellipse((cx + 1, 61, cx + 7, 67), fill=(38, 42, 56, 255))
        bd.polygon([(cx - 5, 68), (cx + 5, 68), (cx, 76)], fill=(255, 176, 59, 255))
        # 脚
        for side in (-1, 1):
            bd.ellipse((cx + side * 22 - 12, 126, cx + side * 22 + 12, 142), fill=(255, 176, 59, 255))
        # 翅膀
        for side in (-1, 1):
            bd.polygon(
                [
                    (cx + side * 44, 62),
                    (cx + side * 70, 80 + lean * 40 * side),
                    (cx + side * 44, 104),
                ],
                fill=(30, 33, 45, 255),
            )
        frames.append(img_body.rotate(lean * 14, resample=Image.BICUBIC).convert("P", palette=Image.ADAPTIVE, colors=32))
    return frames


# ---------------------------------------------------------------- 6. 视频示例 mp4
def sample_mp4():
    frames_dir = os.path.join(OUT, "_frames_tmp")
    os.makedirs(frames_dir, exist_ok=True)
    n = 48
    for i in range(n):
        t = i / n
        img = Image.new("RGB", (SIZE, SIZE), (18, 18, 24))
        d = ImageDraw.Draw(img)
        # 弹跳的小球 + 拖影
        x = SIZE / 2
        y = 24 + (1 - abs(math.sin(t * 3 * math.pi))) * 100
        for k in range(1, 7):
            alpha = 1 - k / 7
            d.ellipse(
                (x - 18 - k * 2, y - 18 + k * 12, x + 18 + k * 2, y + 18 + k * 12),
                fill=(int(120 * alpha) + 20, int(180 * alpha) + 20, int(255 * alpha) + 20),
            )
        d.ellipse((x - 18, y - 18, x + 18, y + 18), fill=(255, 255, 255))
        d.ellipse((x - 8, y - 4, x - 4, y + 4), fill=(40, 40, 60))
        d.ellipse((x + 4, y - 4, x + 8, y + 4), fill=(40, 40, 60))
        d.arc((x - 9, y + 2, x + 9, y + 14), start=10, end=170, fill=(40, 40, 60), width=2)
        img.save(os.path.join(frames_dir, f"f{i:03d}.png"))

    out = os.path.join(OUT, "bounce.mp4")
    for encoder in ("libx264", "libopenh264", "mpeg4"):
        if subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-encoders"],
            capture_output=True, text=True
        ).stdout.find(encoder) == -1:
            continue
        subprocess.run(
            [
                "ffmpeg", "-y", "-loglevel", "error",
                "-framerate", "24",
                "-i", os.path.join(frames_dir, "f%03d.png"),
                "-c:v", encoder,
                "-pix_fmt", "yuv420p",
                "-crf", "30",
                "-movflags", "+faststart",
                "-an",
                out,
            ],
            check=False,
        )
        if os.path.exists(out) and os.path.getsize(out) > 0:
            break
    shutil.rmtree(frames_dir, ignore_errors=True)
    if os.path.exists(out):
        print(f"{'bounce.mp4':22s} {os.path.getsize(out) / 1024:6.1f} KB")
    else:
        print("⚠️ ffmpeg 生成视频失败，已跳过")


if __name__ == "__main__":
    save(bobbing_face(), "bob_face.gif")
    save(heartbeat(), "heart_beat.gif", duration=110)
    save(spinner(), "spinner.gif")
    save(dvd_bounce(), "dvd_bounce.gif", duration=80)
    save(wobble_penguin(), "penguin.gif", duration=100)
    sample_mp4()
    print(f"\n→ {OUT}")
