#!/usr/bin/env python3
"""PDF漫画ビューアーのアプリアイコンを生成する。

1024x1024 のマスターPNG (build/icon-work/AppIcon-1024.png) を描画する。
その後、sips と iconutil を使って Resources/AppIcon.icns を組み立てる手順は
このスクリプトの外（README または呼び出し側コマンド）で行う。
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = PROJECT_ROOT / "build" / "icon-work"
OUT_PATH = OUT_DIR / "AppIcon-1024.png"

CANVAS = 1024
PADDING = 40
CONTENT = CANVAS - PADDING * 2  # 944
CORNER_RADIUS = round(CONTENT * 0.22)

ORANGE = (255, 159, 64)
RED = (224, 48, 56)
CREAM = (255, 244, 224)
WHITE = (255, 255, 255)
SHADOW = (0, 0, 0)


def make_background(size: int) -> Image.Image:
    """角丸スクエアに、左上オレンジ→右下赤の斜めグラデーションを敷いた背景を作る。"""
    grad = Image.linear_gradient("L")  # 256x256, 上=黒(0) 下=白(255) の垂直グラデーション
    big = grad.resize((size * 2, size * 2), Image.BICUBIC)
    rotated = big.rotate(45, expand=True, resample=Image.BICUBIC)
    cx, cy = rotated.width // 2, rotated.height // 2
    half = size // 2
    mask_grad = rotated.crop((cx - half, cy - half, cx + half, cy + half))

    orange_layer = Image.new("RGB", (size, size), ORANGE)
    red_layer = Image.new("RGB", (size, size), RED)
    # mask_grad: 左上が黒(0)寄り・右下が白(255)寄りになるので、
    # 黒=オレンジ, 白=赤 として composite する。
    diagonal = Image.composite(red_layer, orange_layer, mask_grad).convert("RGBA")

    rounded_mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(rounded_mask)
    mask_draw.rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=CORNER_RADIUS, fill=255
    )

    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bg.paste(diagonal, (0, 0), rounded_mask)

    # 上部にごく薄いハイライトを足して、艶のあるmacOSアイコン風の質感にする。
    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hl_draw = ImageDraw.Draw(highlight)
    hl_draw.ellipse(
        (-size * 0.2, -size * 0.55, size * 1.2, size * 0.55),
        fill=(255, 255, 255, 60),
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(size * 0.03))
    highlight.putalpha(Image.composite(highlight.split()[3], Image.new("L", (size, size), 0), rounded_mask))
    bg = Image.alpha_composite(bg, highlight)

    return bg, rounded_mask


def draw_book(canvas: Image.Image, center: tuple[float, float], scale: float) -> None:
    """横長の見開き本。左右ページを背骨で分け、外側の角だけを丸める。"""
    page_w = 260 * scale
    page_h = 300 * scale
    radius = 30 * scale
    cx, cy = center
    top_y = cy - page_h / 2
    bottom_y = top_y + page_h

    left_box = (cx - page_w, top_y, cx, bottom_y)
    right_box = (cx, top_y, cx + page_w, bottom_y)

    # 下に薄い紙の重なりを2枚のぞかせて、束になった本の厚みを出す
    stack_color = (214, 150, 100, 255)
    for i in (2, 1):
        off = 6 * scale * i
        draw = ImageDraw.Draw(canvas, "RGBA")
        draw.rounded_rectangle(
            (cx - page_w + off, top_y + off, cx + page_w + off, bottom_y + off),
            radius=radius,
            fill=stack_color,
        )

    # 影(ドロップシャドウ)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    offset = 10 * scale
    sdraw.rounded_rectangle(
        (cx - page_w + offset, top_y + offset, cx + page_w + offset, bottom_y + offset),
        radius=radius,
        fill=(0, 0, 0, 100),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(14 * scale))
    canvas.alpha_composite(shadow)

    draw = ImageDraw.Draw(canvas, "RGBA")
    draw.rounded_rectangle(
        left_box, radius=radius, fill=(244, 224, 194, 255), corners=(True, False, False, True)
    )
    draw.rounded_rectangle(
        right_box, radius=radius, fill=CREAM, corners=(False, True, True, False)
    )

    # 背骨(spine)の折り目
    spine_w = max(3, round(6 * scale))
    draw.line([(cx, top_y + 4 * scale), (cx, bottom_y - 4 * scale)], fill=(190, 135, 95, 255), width=spine_w)

    # 右ページにコマ割り風の短い線を数本
    line_color = (205, 155, 115, 255)
    for i, frac in enumerate((0.28, 0.48, 0.68)):
        y = top_y + page_h * frac
        x0 = cx + page_w * 0.16
        x1 = cx + page_w * (0.82 - i * 0.10)
        draw.line([(x0, y), (x1, y)], fill=line_color, width=max(2, round(5 * scale)))


def draw_speech_bubble(canvas: Image.Image, center: tuple[float, float], scale: float) -> None:
    w, h = 300 * scale, 190 * scale
    cx, cy = center
    box = (cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
    radius = 46 * scale

    tail = [
        (cx - w * 0.22, cy + h * 0.30),
        (cx - w * 0.44, cy + h * 0.62),
        (cx + w * 0.02, cy + h * 0.36),
    ]

    # 影
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    off = 10 * scale
    sdraw.rounded_rectangle(
        (box[0] + off, box[1] + off, box[2] + off, box[3] + off), radius=radius, fill=(0, 0, 0, 90)
    )
    sdraw.polygon([(x + off, y + off) for x, y in tail], fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(12 * scale))
    canvas.alpha_composite(shadow)

    draw = ImageDraw.Draw(canvas, "RGBA")
    draw.polygon(tail, fill=WHITE)
    draw.rounded_rectangle(box, radius=radius, fill=WHITE)

    # 吹き出しの中の短い線(コマの中のセリフを示唆)
    line_color = (230, 120, 60, 255)
    for i, frac in enumerate((0.36, 0.58)):
        y = box[1] + h * frac
        x0 = box[0] + w * 0.18
        x1 = box[0] + w * (0.82 - i * 0.16)
        draw.line([(x0, y), (x1, y)], fill=line_color, width=max(2, round(5 * scale)))


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    bg, rounded_mask = make_background(CANVAS)
    canvas = bg.copy()

    book_center = (CANVAS * 0.47, CANVAS * 0.60)
    draw_book(canvas, book_center, scale=1.55)

    bubble_center = (CANVAS * 0.72, CANVAS * 0.32)
    draw_speech_bubble(canvas, bubble_center, scale=1.05)

    # 角丸の外側にはみ出た部分を最終マスクで切り落とす
    final = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    final.paste(canvas, (0, 0), rounded_mask)

    final.save(OUT_PATH)
    print(f"書き出し: {OUT_PATH}")


if __name__ == "__main__":
    main()
