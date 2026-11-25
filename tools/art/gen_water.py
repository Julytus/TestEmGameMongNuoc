"""Sinh texture dữ liệu cho mặt nước (water.gdshader chỉ đọc + cuộn theo TIME, không noise thủ tục trong fragment).

Chạy:  python tools/art/gen_water.py
Kết quả (ghi đè, deterministic – seed cố định):
  assets/art/environment/water/water_noise.png    256x256 RGB, lát liền 2 chiều
        lưới CELLS x CELLS ô value noise (8 texel/ô, smoothstep) – thay terrain_noise cũ
        R = N(u, v) tại tâm texel (u, v tính theo ô)
        G = 0.5 + DERIV_SCALE * (N(u + DERIV_STEP, v) - N(u, v))   sai phân theo x → pháp tuyến gợn
        B = 0.5 + DERIV_SCALE * (N(u, v + DERIV_STEP) - N(u, v))   sai phân theo z
  assets/art/environment/water/water_sparkle.png  128x128 L, white noise (mỗi pixel độc lập) – đốm lấp lánh
  assets/art/environment/water/water_ripple_ring.png  flipbook RING_FRAMES khung x RING_SIZE px, RGB
        vòng gợn bước chân (WaterRipples vẽ cộng dồn vào SubViewport): R = độ cao sóng (2 đỉnh đồng tâm loang ra,
        tắt dần), G = bọt (viền đỉnh đầu, chỉ 45% đầu đời vòng). Khớp water_ripples.gd: RING_FRAMES.
Shader phải khớp: noise_cells = CELLS (32), giải mã d = (gb - 0.5) / DERIV_SCALE, bước sai phân 0.4 ô.
Texture DỮ LIỆU (tuyến tính) – shader không dùng source_color. Không vẽ tay.
"""
from __future__ import annotations

import math
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


RING_FRAMES = 12
# = đường kính vòng bước chân (2 m) × 16 px/m → WaterRipples vẽ đúng 1:1, không co giãn.
RING_SIZE = 32


def _bump(d: float, width: float) -> float:
    """Gò cos² rộng width quanh 0 (0 ngoài |d| >= width)."""
    if abs(d) >= width:
        return 0.0
    c = math.cos(math.pi * 0.5 * d / width)
    return c * c


def gen_ripple_ring(frames: int = RING_FRAMES, size: int = RING_SIZE) -> Image.Image:
    img = Image.new("RGB", (frames * size, size))
    px = img.load()
    half = size * 0.5
    for i in range(frames):
        t = (i + 0.5) / frames
        lead = 0.12 + 0.83 * (1.0 - (1.0 - t) ** 2)  # loang nhanh rồi chậm dần
        decay = (1.0 - t) ** 1.2
        foam_k = max(0.0, 1.0 - t / 0.45)
        for y in range(size):
            for x in range(size):
                r = math.hypot(x + 0.5 - half, y + 0.5 - half) / half
                h = 0.0
                for k, amp in enumerate((1.0, 0.5)):
                    rk = lead - 0.3 * k
                    if rk > 0.06:
                        h += amp * _bump(r - rk, 0.1)
                foam = foam_k * _bump(r - lead, 0.07)
                px[i * size + x, y] = (_byte(min(h * decay, 1.0)), _byte(min(foam, 1.0)), 0)
    return img


def main() -> None:
    WATER_DIR.mkdir(parents=True, exist_ok=True)
    gen_noise().save(WATER_DIR / "water_noise.png")
    gen_sparkle().save(WATER_DIR / "water_sparkle.png")
    gen_ripple_ring().save(WATER_DIR / "water_ripple_ring.png")
    print("OK ->", WATER_DIR)


if __name__ == "__main__":
    main()
