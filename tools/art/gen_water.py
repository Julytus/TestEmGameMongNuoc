"""Sinh texture dữ liệu cho mặt nước (water.gdshader chỉ đọc + cuộn theo TIME, không noise thủ tục trong fragment).

Chạy:  python tools/art/gen_water.py
Kết quả (ghi đè, deterministic – seed cố định):
  assets/art/environment/water/water_noise.png    256x256 RGB, lát liền 2 chiều
        lưới CELLS x CELLS ô value noise (8 texel/ô, smoothstep) – thay terrain_noise cũ
        R = N(u, v) tại tâm texel (u, v tính theo ô)
        G = 0.5 + DERIV_SCALE * (N(u + DERIV_STEP, v) - N(u, v))   sai phân theo x → pháp tuyến gợn
        B = 0.5 + DERIV_SCALE * (N(u, v + DERIV_STEP) - N(u, v))   sai phân theo z
  assets/art/environment/water/water_sparkle.png  128x128 L, white noise (mỗi pixel độc lập) – đốm lấp lánh
Shader phải khớp: noise_cells = CELLS (32), giải mã d = (gb - 0.5) / DERIV_SCALE, bước sai phân 0.4 ô.
Texture DỮ LIỆU (tuyến tính) – shader không dùng source_color. Không vẽ tay.
"""
from __future__ import annotations

import random
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
WATER_DIR = ROOT / "assets" / "art" / "environment" / "water"

CELLS = 32
DERIV_SCALE = 0.8
DERIV_STEP = 0.4


def value_noise_grid(cells: int, rng: random.Random) -> list[list[float]]:
    return [[rng.random() for _ in range(cells)] for _ in range(cells)]


def noise_at(grid: list[list[float]], cells: int, u: float, v: float) -> float:
    """Value noise smoothstep wrap (như tileable_noise trong gen_terrain.py) tại tọa độ ô (u, v) bất kỳ."""
    fu, fv = int(u // 1), int(v // 1)
    tx, ty = u - fu, v - fv
    x0, y0 = fu % cells, fv % cells
    x1, y1 = (x0 + 1) % cells, (y0 + 1) % cells
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    a = grid[y0][x0] + (grid[y0][x1] - grid[y0][x0]) * tx
    b = grid[y1][x0] + (grid[y1][x1] - grid[y1][x0]) * tx
    return a + (b - a) * ty


def _byte(v: float) -> int:
    return max(0, min(255, round(v * 255)))


def gen_noise(size: int = 256, cells: int = CELLS, seed: int = 71) -> Image.Image:
    grid = value_noise_grid(cells, random.Random(seed))
    step = size / cells
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        v = (y + 0.5) / step
        for x in range(size):
            u = (x + 0.5) / step
            n = noise_at(grid, cells, u, v)
            dx = noise_at(grid, cells, u + DERIV_STEP, v) - n
            dz = noise_at(grid, cells, u, v + DERIV_STEP) - n
            px[x, y] = (_byte(n), _byte(0.5 + DERIV_SCALE * dx), _byte(0.5 + DERIV_SCALE * dz))
    return img


def gen_sparkle(size: int = 128, seed: int = 73) -> Image.Image:
    rng = random.Random(seed)
    img = Image.new("L", (size, size))
    img.putdata([rng.randrange(256) for _ in range(size * size)])
    return img


def main() -> None:
    WATER_DIR.mkdir(parents=True, exist_ok=True)
    gen_noise().save(WATER_DIR / "water_noise.png")
    gen_sparkle().save(WATER_DIR / "water_sparkle.png")
    print("OK ->", WATER_DIR)


if __name__ == "__main__":
    main()
