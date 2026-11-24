#!/usr/bin/env python3
"""生成 iOS 图标和启动画面。只依赖 Python 3 标准库。"""

import struct
import zlib
from pathlib import Path


OUTPUT = Path(__file__).resolve().parents[1] / "resources" / "ios"
SIDE = 32
ICON_SIZES = (40, 58, 60, 76, 80, 87, 114, 120, 128, 136, 152, 167, 180, 192, 1024)

NIGHT = bytes.fromhex("120f17")
AMBER = bytes.fromhex("ffc050")
CRIMSON = bytes.fromhex("d83838")
BLUE = bytes.fromhex("5a90d0")
GREEN = bytes.fromhex("78c850")
CITY = bytes.fromhex("252238")
STEEL = bytes.fromhex("36547d")
SHADOW = bytes.fromhex("1a283c")
MOSS = bytes.fromhex("3f773f")
ACID = bytes.fromhex("b8eb76")


def emblem():
    """在 32 × 32 像素上绘制夜城、城盾和被瞄准的僵尸。"""
    pixels = [[NIGHT] * SIDE for _ in range(SIDE)]

    def rect(x, y, width, height, color):
        for row in pixels[y : y + height]:
            row[x : x + width] = [color] * width

    for x, y, width in ((0, 15, 4), (3, 12, 4), (6, 19, 4),
                        (23, 17, 4), (26, 11, 4), (30, 15, 2)):
        rect(x, y, width, 28 - y, CITY)
    for x, y in ((2, 18), (4, 15), (4, 20), (27, 14), (27, 18), (30, 21)):
        rect(x, y, 1, 1, STEEL)
    rect(0, 28, SIDE, 1, CITY)

    # 城垛、盾面和台阶状的盾尖。
    for x, width in ((6, 5), (14, 4), (21, 5)):
        rect(x, 5, width, 4, BLUE)
    rect(6, 8, 20, 14, BLUE)
    rect(7, 22, 18, 2, BLUE)
    rect(9, 24, 14, 2, BLUE)
    rect(11, 26, 10, 1, BLUE)
    rect(13, 27, 6, 1, BLUE)
    rect(15, 28, 2, 1, BLUE)
    rect(8, 10, 16, 12, SHADOW)
    rect(9, 22, 14, 1, SHADOW)
    rect(11, 23, 10, 2, SHADOW)
    rect(13, 25, 6, 1, SHADOW)
    rect(15, 26, 2, 1, SHADOW)
    rect(6, 11, 1, 11, STEEL)
    rect(25, 11, 1, 11, STEEL)

    # 僵尸的额头、破损的右颊和两颗牙。
    face = (
        "..GGGGGG..",
        ".GHHGGGGG.",
        "GGGGGGGGGS",
        "G.D.GG.D.S",
        "GGDRGGDRGS",
        "GGGGGGGG.S",
        ".GG.D.DGS.",
        ".GGSHSHGS.",
        "..GSSSSS..",
        "...SSSS...",
    )
    colors = {"G": GREEN, "H": ACID, "S": MOSS, "D": NIGHT, "R": CRIMSON}
    for y, row in enumerate(face, 12):
        for x, symbol in enumerate(row, 11):
            if symbol in colors:
                pixels[y][x] = colors[symbol]

    # 四角瞄准标记和盾尖上的警报灯。
    for x, left in ((9, True), (20, False)):
        for y, top in ((11, True), (21, False)):
            rect(x, y, 3, 1, AMBER)
            rect(x if left else x + 2, y if top else y - 2, 1, 3, AMBER)
    rect(14, 24, 4, 1, CRIMSON)
    rect(15, 24, 2, 1, AMBER)
    return pixels


def scale_pixels(pixels, size):
    """按最近邻采样，保留每个像素的原色。"""
    source_indices = [(2 * i + 1) * SIDE // (2 * size) for i in range(size)]
    return [
        b"".join(pixels[y][x] for x in source_indices)
        for y in source_indices
    ]


def png_chunk(kind, data):
    crc = zlib.crc32(kind + data)
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", crc)


def write_png(path, width, height, rows):
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", zlib.compress(b"".join(b"\0" + row for row in rows), 9))
        + png_chunk(b"IEND", b"")
    )


def write_launch_image(filename, density, pixels):
    # 两张图使用相同的逻辑尺寸，徽标固定为 96 点。
    width, height, size = 640 * density, 360 * density, 96 * density
    horizontal_padding = NIGHT * ((width - size) // 2)
    vertical_padding = [NIGHT * width] * ((height - size) // 2)
    centered = [
        horizontal_padding + row + horizontal_padding
        for row in scale_pixels(pixels, size)
    ]
    write_png(OUTPUT / filename, width, height, vertical_padding + centered + vertical_padding)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    pixels = emblem()
    for size in ICON_SIZES:
        write_png(OUTPUT / f"icon_{size}.png", size, size, scale_pixels(pixels, size))
    write_launch_image("launch_bg.png", 2, pixels)
    write_launch_image("launch_bg_3x.png", 3, pixels)
    print(f"已生成 {len(ICON_SIZES)} 张图标和 2 张启动图。")


if __name__ == "__main__":
    main()
