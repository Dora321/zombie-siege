#!/usr/bin/env python3
"""从 Fusion Pixel 完整字体裁出游戏用到的字，改了界面文案后重新跑一次。

用法（需要 pip install fonttools）：
    python3 tools/build_font.py path/to/fusion-pixel-12px-proportional-zh_hans.ttf

字集 = 可打印 ASCII + scripts/ 和 scenes/ 里出现的所有非 ASCII 字符。
"""
import pathlib
import sys

from fontTools import subset

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "resources/fonts/fusion-pixel-12px-proportional-zh_hans.subset.ttf"
CHARS_FILE = ROOT / "tools/font_chars.txt"


def collect_chars() -> str:
    chars = {chr(c) for c in range(0x20, 0x7F)}
    for folder in ("scripts", "scenes"):
        for path in (ROOT / folder).rglob("*"):
            if path.suffix in (".gd", ".tscn"):
                chars |= {c for c in path.read_text(encoding="utf-8") if ord(c) >= 0x80}
    return "".join(sorted(chars))


def main() -> None:
    chars = collect_chars()
    CHARS_FILE.write_text(chars, encoding="utf-8")
    options = subset.Options()
    options.name_IDs = ["*"]  # 保留字体内的版权和许可证信息
    options.notdef_outline = True
    options.hinting = False
    font = subset.load_font(sys.argv[1], options)
    subsetter = subset.Subsetter(options)
    subsetter.populate(text=chars)
    subsetter.subset(font)
    subset.save_font(font, str(OUTPUT), options)
    print(f"{len(chars)} 字 -> {OUTPUT.name} {OUTPUT.stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    main()
