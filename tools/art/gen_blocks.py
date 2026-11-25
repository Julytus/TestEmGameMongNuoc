"""Sinh atlas pixel cho block 1 m (đất / cỏ / đá) — dùng bởi build_block_library.gd + block_material.tres.

Chạy:  python tools/art/gen_blocks.py
Kết quả (ghi đè, deterministic theo seed):
  assets/art/blocks/blocks_atlas.png   128x32 RGB, 4 ô 32x32 (32 px = 1 m) theo thứ tự TILES:
        0 grass_top   mặt trên khối cỏ
        1 grass_side  cạnh khối cỏ: viền cỏ 5–9 px răng cưa ở trên, phần dưới là đất
        2 dirt        mọi mặt khối đất + mặt đáy khối cỏ
        3 stone       mọi mặt khối đá
Ô cỏ/đất sinh bằng CHÍNH hàm mặt đất của gen_terrain.py (size 32) → cùng phong cách terrain; đá theo tông rock.gdshader.
Mỗi ô lát liền (noise wrap) để khối xếp cạnh nhau không lộ đường nối.
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_terrain import (  # noqa: E402
    GRASS_EDGE_DARK, GRASS_PALETTE, PX_PER_M, fbm, gen_dirt_ground, gen_grass_ground, hexc, quantize,
)

ROOT = Path(__file__).resolve().parents[2]
OUT_PATH = ROOT / "assets" / "art" / "blocks" / "blocks_atlas.png"

TILE = PX_PER_M  # 1 mặt khối = 1 m = 32 px, cùng mật độ với mặt đất terrain
TILES = ["grass_top", "grass_side", "dirt", "stone"]
# Tông đá theo rock.gdshader (stone_color 0.52,0.49,0.48; crack 0.24,0.22,0.29; speck 0.72,0.68,0.6)
STONE_PALETTE = [hexc(c) for c in ("#6c6670", "#7a7379", "#877f7c", "#948b86")]
STONE_CRACK = hexc("#3d384a")
STONE_SPECK = hexc("#b8ad99")


def gen_grass_side(dirt: Image.Image, top: Image.Image, seed: int = 303) -> Image.Image:
    """Cạnh khối cỏ: viền cỏ 5–9 px răng cưa ở trên (pixel cuối xanh đậm như mép cỏ terrain), dưới là đất."""
    img = dirt.copy()
    px = img.load()
    tp = top.load()
    rng = random.Random(seed)
    depth = 7
    for x in range(TILE):
        depth = max(5, min(9, depth + rng.choice((-2, -1, 0, 0, 1, 2))))
        for y in range(depth):
            px[x, y] = tp[x, y]
        px[x, depth] = GRASS_EDGE_DARK
        if rng.random() < 0.3:  # răng dài thêm 1–2 px
            for k in range(1, rng.choice((2, 3))):
                px[x, depth + k] = GRASS_EDGE_DARK
    for x in range(TILE):  # hàng trên cùng sáng — mép khối bắt nắng
        if rng.random() < 0.5:
            px[x, 0] = GRASS_PALETTE[-1]
    return img


def gen_stone(seed: int = 404) -> Image.Image:
    rng = random.Random(seed)
    n = fbm(TILE, rng, ((2, 0.55), (4, 0.3), (8, 0.15)))
    img = Image.new("RGB", (TILE, TILE))
    px = img.load()
    for y in range(TILE):
        for x in range(TILE):
            px[x, y] = STONE_PALETTE[quantize((n[y][x] - 0.5) * 1.5 + 0.5, x, y, len(STONE_PALETTE), 0.2)]
    for _ in range(5):  # khe nứt gấp khúc, wrap
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        for _ in range(rng.randint(3, 6)):
            px[x % TILE, y % TILE] = STONE_CRACK
            x += rng.choice((1, 1, 0))
            y += rng.choice((1, 0, -1))
    for _ in range(8):
        px[rng.randrange(TILE), rng.randrange(TILE)] = STONE_SPECK
    return img


def gen_atlas() -> Image.Image:
    top = gen_grass_ground(TILE, seed=101)
    dirt = gen_dirt_ground(TILE, seed=202)
    tiles = {"grass_top": top, "grass_side": gen_grass_side(dirt, top), "dirt": dirt, "stone": gen_stone()}
    atlas = Image.new("RGB", (TILE * len(TILES), TILE))
    for i, name in enumerate(TILES):
        atlas.paste(tiles[name], (i * TILE, 0))
    return atlas


def main() -> None:
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    atlas = gen_atlas()
    atlas.save(OUT_PATH)
    if "--preview" in sys.argv:
        atlas.resize((atlas.width * 8, atlas.height * 8), Image.NEAREST).save(sys.argv[sys.argv.index("--preview") + 1])
    print("OK ->", OUT_PATH)


if __name__ == "__main__":
    main()
