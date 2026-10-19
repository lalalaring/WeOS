#!/usr/bin/env python3
"""生成 WeOS 品牌资产（纯标准库，无第三方依赖）。

输出：
  os-config/includes.chroot/usr/share/backgrounds/weos/weos-default.png   1920x1080
  os-config/includes.chroot/etc/calamares/branding/weos/productLogo.png    256x256
  os-config/includes.chroot/etc/calamares/branding/weos/productIcon.png    128x128
  os-config/includes.chroot/etc/calamares/branding/weos/welcome.png        800x400
  os-config/includes.chroot/usr/share/plymouth/themes/weos/background.png  1920x1080
"""
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INC = os.path.join(ROOT, "os-config", "includes.chroot")

BG_TOP = (11, 16, 38)
BG_BOTTOM = (26, 34, 66)
ACCENT = (86, 132, 255)
ACCENT2 = (140, 92, 255)
INK = (240, 244, 255)


def write_png(path, width, height, pixel):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        row = bytearray()
        for x in range(width):
            r, g, b = pixel(x, y)
            row += bytes((r, g, b))
        raw += row

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    blob = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
        + chunk(b"IEND", b"")
    )
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(blob)
    print("  ->", os.path.relpath(path, ROOT))


def mix(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(round(a + (b - a) * t)) for a, b in zip(c1, c2))


def seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    L2 = vx * vx + vy * vy
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, (wx * vx + wy * vy) / L2))
    dx, dy = px - (ax + t * vx), py - (ay + t * vy)
    return math.hypot(dx, dy)


def w_mark_dist(px, py, cx, cy, size):
    """以 (cx,cy) 为中心、边长 size 的 'W' 折线距离"""
    hw = size / 2.0
    h = size * 0.62
    top = cy - h / 2.0
    bot = cy + h / 2.0
    pts = [
        (cx - hw, top),
        (cx - hw * 0.42, bot),
        (cx, top + h * 0.30),
        (cx + hw * 0.42, bot),
        (cx + hw, top),
    ]
    return min(
        seg_dist(px, py, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1])
        for i in range(len(pts) - 1)
    )


def wallpaper(w, h, mark_size, dark=False):
    def px(x, y):
        u, v = x / w, y / h
        base = mix(BG_TOP, BG_BOTTOM, (u * 0.35 + v * 0.65))
        # 右上角光晕
        d = math.hypot((u - 0.78) * 1.4, (v - 0.22))
        glow = max(0.0, 1.0 - d / 0.72) ** 2
        base = mix(base, ACCENT, glow * 0.55)
        # 左下角紫色光晕
        d2 = math.hypot((u - 0.14) * 1.6, (v - 0.88))
        glow2 = max(0.0, 1.0 - d2 / 0.62) ** 2
        base = mix(base, ACCENT2, glow2 * 0.35)
        # 品牌标记
        cx, cy = w * 0.5, h * 0.5
        dist = w_mark_dist(x, y, cx, cy, mark_size)
        stroke = max(2.0, mark_size * 0.055)
        edge = 1.0 - max(0.0, min(1.0, (dist - stroke) / 1.6))
        if edge > 0:
            t = 0.88 if not dark else 0.92
            base = mix(base, INK, edge * t)
        # 暗角
        vg = 1.0 - 0.35 * (((u - 0.5) ** 2 + (v - 0.5) ** 2) ** 0.5) * 2
        return tuple(int(c * max(0.45, min(1.0, vg))) for c in base)

    return px


def logo(size, ratio=1.0):
    def px(x, y):
        u, v = x / size, y / size
        base = mix(BG_TOP, (18, 24, 52), 0.5 + 0.5 * (1 - v))
        d = math.hypot(u - 0.72, v - 0.26)
        base = mix(base, ACCENT, max(0.0, 1.0 - d / 0.8) ** 2 * 0.6)
        dist = w_mark_dist(x, y, size * 0.5, size * 0.5, size * 0.60 * ratio)
        stroke = max(2.0, size * 0.045)
        edge = 1.0 - max(0.0, min(1.0, (dist - stroke) / 1.4))
        return mix(base, INK, edge * 0.95)

    return px


def main():
    print("生成 WeOS 品牌资产")
    write_png(
        os.path.join(INC, "usr/share/backgrounds/weos/weos-default.png"),
        1920, 1080, wallpaper(1920, 1080, 420),
    )
    write_png(
        os.path.join(INC, "usr/share/plymouth/themes/weos/background.png"),
        1920, 1080, wallpaper(1920, 1080, 300, dark=True),
    )
    write_png(
        os.path.join(INC, "etc/calamares/branding/weos/productLogo.png"),
        256, 256, logo(256),
    )
    write_png(
        os.path.join(INC, "etc/calamares/branding/weos/productIcon.png"),
        128, 128, logo(128),
    )
    write_png(
        os.path.join(INC, "etc/calamares/branding/weos/welcome.png"),
        800, 400, wallpaper(800, 400, 210),
    )
    print("完成")


if __name__ == "__main__":
    main()
