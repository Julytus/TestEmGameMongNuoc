"""Sinh atlas pixel cho block 1 m (đất / cỏ / đá) — dùng bởi build_block_library.gd + block_material.tres.

Chạy:  python tools/art/gen_blocks.py
Kết quả (ghi đè, deterministic theo seed):
  assets/art/blocks/blocks_atlas.png   128x32 RGB, 4 ô 32x32 (32 px = 1 m) theo thứ tự TILES:
        0 grass_top   mặt trên khối cỏ
        1 grass_side  cạnh khối cỏ: lớp cỏ rủ mép lượn mềm ở trên, phần dưới là đất
        2 dirt        mọi mặt khối đất + mặt đáy khối cỏ
        3 stone       mọi mặt khối đá (cuội Voronoi bo mép)
Ô cỏ/đất sinh bằng CHÍNH hàm mặt đất của gen_terrain.py (size 32) → cùng phong cách terrain; đá theo tông rock.gdshader.
Mỗi ô lát liền (noise wrap) để khối xếp cạnh nhau không lộ đường nối.
"""
from __future__ import annotations

import math
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
# Tông đá theo rock.gdshader (stone_color 0.52,0.49,0.48; speck 0.72,0.68,0.6)
STONE_PALETTE = [hexc(c) for c in ("#6c6670", "#7a7379", "#877f7c", "#948b86")]
STONE_SPECK = hexc("#b8ad99")
STONE_GAP = hexc("#4c4656")  # khe giữa viên cuội — dịu hơn STONE_CRACK để khối không bị "lưới" gắt


def gen_grass_side(dirt: Image.Image, top: Image.Image, seed: int = 303) -> Image.Image:
    """Cạnh khối cỏ: lớp cỏ rủ xuống mép lượn mềm (sóng sin lát liền + vài giọt cỏ tròn đầu), viền xanh đậm 1 px,
    dưới đó 1 px bóng đổ lên đất. 2 hàng trên cùng sáng — trùng dải bo cạnh của mesh nên mép khối bắt nắng."""
    img = dirt.copy()
    px = img.load()
    tp = top.load()
    rng = random.Random(seed)
    ph1, ph2 = rng.random() * math.tau, rng.random() * math.tau
    drips = [(rng.randrange(TILE), rng.choice((3, 4, 5)), rng.choice((4, 5, 6))) for _ in range(3)]  # (tâm, rộng, dài)
    shade = hexc("#94603a")
    for x in range(TILE):
        d = 7.0 + 1.6 * math.sin(math.tau * x / TILE * 2 + ph1) + 0.9 * math.sin(math.tau * x / TILE * 5 + ph2)
        for cx, w, length in drips:
            dx = min(abs(x - cx), TILE - abs(x - cx))  # khoảng cách wrap
            if dx < w:
                d += length * math.cos(dx / w * math.pi / 2) ** 2  # đầu giọt tròn
        depth = int(round(d))
        for y in range(depth):
            px[x, y] = tp[x, y]
        px[x, depth - 1] = GRASS_PALETTE[0]
        px[x, depth] = GRASS_EDGE_DARK
        if depth + 1 < TILE:
            px[x, depth + 1] = shade
        px[x, 0] = GRASS_PALETTE[-1]
        if (x + 1) % 3:  # hàng thứ 2 sáng lốm đốm
            px[x, 1] = GRASS_PALETTE[-1]
    return img


def gen_stone(seed: int = 404) -> Image.Image:
    """Đá cuội: Voronoi lát liền (~13 viên/ô) — khe tối giữa viên, mỗi viên bo mép: sáng ở mép trên-trái,
    tối ở mép dưới-phải (nắng chéo), lòng viên tông theo palette ± noise nhẹ."""
    rng = random.Random(seed)
    n = fbm(TILE, rng, ((4, 0.6), (8, 0.4)))
    grid = 4
    cell = TILE / grid
    pts: list[tuple[float, float, int]] = []
    for gy in range(grid):
        for gx in range(grid):
            if rng.random() < 0.2:
                continue  # bỏ vài điểm → viên to/nhỏ khác nhau
            pts.append(((gx + 0.2 + rng.random() * 0.6) * cell, (gy + 0.2 + rng.random() * 0.6) * cell,
                        rng.randrange(1, len(STONE_PALETTE))))
    img = Image.new("RGB", (TILE, TILE))
    px = img.load()

    def nearest(x: float, y: float) -> tuple[float, float, int, float, float]:
        best = (1e9, 1e9, 0, 0.0, 0.0)
        for sx, sy, tone in pts:
            dx = (x - sx + TILE / 2) % TILE - TILE / 2
            dy = (y - sy + TILE / 2) % TILE - TILE / 2
            dd = math.hypot(dx, dy)
            if dd < best[0]:
                best = (dd, best[0], tone, dx, dy)
            elif dd < best[1]:
                best = (best[0], dd, best[2], best[3], best[4])
        return best

    for y in range(TILE):
        for x in range(TILE):
            d1, d2, tone, dx, dy = nearest(x + 0.5, y + 0.5)
            edge = d2 - d1  # 0 trên khe
            if edge < 1.1:
                px[x, y] = STONE_GAP
                continue
            idx = tone + (1 if n[y][x] > 0.6 else -1 if n[y][x] < 0.4 else 0)
            if edge < 3.2:  # dải bo mép viên: hướng ra ngoài so với tâm viên
                lean = (-dx - dy) / max(d1, 0.01)  # >0: phía trên-trái
                idx += 1 if lean > 0.35 else -1 if lean < -0.35 else 0
            px[x, y] = STONE_PALETTE[max(0, min(len(STONE_PALETTE) - 1, idx))]
    for _ in range(6):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        if px[x, y] != STONE_GAP:
            px[x, y] = STONE_SPECK
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
