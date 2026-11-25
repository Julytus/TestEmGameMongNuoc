"""Sinh layout cho level stress bench (96x96 m) bằng cách ghép 2x2 gương từ layout meadow_road.

Chạy:  python tools/art/gen_stress_layout.py
Nguồn: src/world/levels/meadow_road/meadow_road_layout.png (48x48 RGBA — R đất, G cỏ cao, B nước, A=0 rừng).
       Ảnh meadow là nguồn sự thật (có chỉnh tay) → KHÔNG gọi gen_terrain.gen_layout(); sửa meadow thì chạy lại script này.
Kết quả (ghi đè, deterministic):
  src/world/levels/bench_stress/bench_stress_layout.png  96x96 RGBA
        ô 0 (trên-trái) nguyên bản, GIỮ hồ · ô 1 (trên-phải) lật X · ô 2 (dưới-trái) lật Y · ô 3 lật cả hai
        ô 1–3: pixel nước (B > 127) → (0, 0, 0, 255) cỏ thấp — chỉ 1 hồ (tránh WaterField 1344x800 dựng ~0,9 s vô ích).
Godot: .import của ảnh phải giữ process/fix_alpha_border=false (ô rừng A=0).
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "src/world/levels/meadow_road/meadow_road_layout.png"
OUT = ROOT / "src/world/levels/bench_stress/bench_stress_layout.png"


def _dry(tile: Image.Image) -> Image.Image:
    tile = tile.copy()
    px = tile.load()
    for y in range(tile.height):
        for x in range(tile.width):
            if px[x, y][2] > 127:
                px[x, y] = (0, 0, 0, 255)
    return tile


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # console Windows cp1252
    src = Image.open(SRC).convert("RGBA")
    w, h = src.size
    out = Image.new("RGBA", (w * 2, h * 2))
    out.paste(src, (0, 0))
    out.paste(_dry(ImageOps.mirror(src)), (w, 0))
    out.paste(_dry(ImageOps.flip(src)), (0, h))
    out.paste(_dry(ImageOps.flip(ImageOps.mirror(src))), (w, h))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.save(OUT)
    spx = src.load()
    water = sum(1 for y in range(h) for x in range(w) if spx[x, y][2] > 127)
    print(f"{OUT.name} {out.width}x{out.height}, nước {water} px (ô 0)")


if __name__ == "__main__":
    main()
