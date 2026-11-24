"""Sinh texture chi tiết cho đá 3D StylizedRock (tách khỏi gen_terrain.py để không ghi đè file khác).

Chạy:  python tools/art/gen_rock.py
Kết quả (ghi đè):
  assets/art/environment/rocks/rock_detail.png   32x32 RGB, lát liền, chiếu triplanar 32 px = 1 m
        R = đốm sáng (khoáng)   G = mặt nạ rêu (noise mượt)   B = khe nứt
Màu thật nằm trong rock.gdshader – texture chỉ là mặt nạ nên ít điểm, để mặt đẽo đọc rõ như pixel art.
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_terrain import fbm  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ROCK_DIR = ROOT / "assets" / "art" / "environment" / "rocks"


def gen_detail(size: int = 32, seed: int = 57) -> Image.Image:
    rng = random.Random(seed)
    moss = fbm(size, rng, ((4, 1.0), (8, 0.45)))
    speck = [[0] * size for _ in range(size)]
    crack = [[0] * size for _ in range(size)]
    for _ in range(18):  # đốm sáng lẻ, đôi khi 2 px
        x, y = rng.randrange(size), rng.randrange(size)
        speck[y][x] = 255
        if rng.random() < 0.3:
            speck[y][(x + 1) % size] = 255
    for _ in range(5):  # khe nứt gấp khúc, wrap 2 chiều
        x, y = rng.randrange(size), rng.randrange(size)
        for _ in range(rng.randint(4, 8)):
            crack[y % size][x % size] = 255
            x += rng.choice((1, 1, 0))
            y += rng.choice((1, 0, -1))
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            g = int(max(0.0, min(1.0, (moss[y][x] - 0.3) * 2.0)) * 255)
            px[x, y] = (speck[y][x], g, crack[y][x])
    return img


def main() -> None:
    ROCK_DIR.mkdir(parents=True, exist_ok=True)
    gen_detail().save(ROCK_DIR / "rock_detail.png")
    print("OK ->", ROCK_DIR)


if __name__ == "__main__":
    main()
