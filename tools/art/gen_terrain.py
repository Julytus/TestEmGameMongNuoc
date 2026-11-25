"""Sinh pixel art địa hình (đất, cỏ, bụi cỏ) + bản đồ bố cục cho Meadow Road.

Chạy:  python tools/art/gen_terrain.py
Kết quả (ghi đè):
  assets/art/environment/terrain/grass_ground.png   128x128, lát liền (tileable), 32 px = 1 m (4 m/ô)
  assets/art/environment/terrain/dirt_ground.png    128x128, lát liền
  assets/art/environment/terrain/edge_fringe.png    128x128 xám, mặt nạ mép răng cưa đất/cỏ (shader terrain)
  assets/art/environment/terrain/grass_tufts.png    6 biến thể bụi cỏ 32x24 (32 px = 1 m)
  assets/art/environment/terrain/flowers.png        4 biến thể hoa dại 16x16
  assets/art/environment/trees/leaves.png           atlas chùm lá (hàng 0 bản rộng, hàng 1 lá kim), xám
  assets/art/environment/trees/bark.png             vỏ cây 16x32
  src/world/levels/meadow_road/meadow_road_layout.png  48x48 RGBA, 1 px = 1 ô 1 m
        R = đường đất, G = cỏ cao, B = nước, A = 0 (ô trong suốt) = rừng

Mọi file đều mở/sửa được bằng Pixelorama. Muốn giữ bản sửa tay thì đừng chạy lại script
(hoặc đổi tên file output).
"""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
TERRAIN_DIR = ROOT / "assets" / "art" / "environment" / "terrain"
TREE_DIR = ROOT / "assets" / "art" / "environment" / "trees"
LEVEL_DIR = ROOT / "src" / "world" / "levels" / "meadow_road"

BAYER4 = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def hexc(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def tileable_noise(size: int, cells: int, rng: random.Random) -> list[list[float]]:
    """Value noise lát liền: lưới cells x cells, nội suy smoothstep, wrap 2 chiều."""
    grid = [[rng.random() for _ in range(cells)] for _ in range(cells)]
    out = [[0.0] * size for _ in range(size)]
    step = size / cells
    for y in range(size):
        for x in range(size):
            gx, gy = x / step, y / step
            x0, y0 = int(gx) % cells, int(gy) % cells
            x1, y1 = (x0 + 1) % cells, (y0 + 1) % cells
            tx, ty = gx - int(gx), gy - int(gy)
            tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
            a = grid[y0][x0] + (grid[y0][x1] - grid[y0][x0]) * tx
            b = grid[y1][x0] + (grid[y1][x1] - grid[y1][x0]) * tx
            out[y][x] = a + (b - a) * ty
    return out


def fbm(size: int, rng: random.Random, octaves: tuple[tuple[int, float], ...]) -> list[list[float]]:
    total = sum(w for _, w in octaves)
    layers = [(tileable_noise(size, c, rng), w) for c, w in octaves]
    return [[sum(l[y][x] * w for l, w in layers) / total for x in range(size)] for y in range(size)]


def quantize(value: float, x: int, y: int, levels: int, dither: float) -> int:
    """Lượng tử hóa 0..1 thành chỉ số bảng màu, có dither Bayer cho cảm giác pixel art."""
    v = value + (BAYER4[y % 4][x % 4] / 16.0 - 0.5) * dither
    return max(0, min(levels - 1, int(v * levels)))


# ---------------------------------------------------------------- Mặt đất cỏ / đất (kiểu ảnh mẫu VL3)
# Nền phẳng: mảng màu rộng, tương phản thấp, dither nhẹ; chi tiết thưa. 32 px = 1 m.
# Dùng chung cho terrain (size 128 = 4 m) và block (size 32 = 1 m, gen_blocks.py) → cùng phong cách.
PX_PER_M = 32
GRASS_PALETTE = [hexc(c) for c in ("#4c8631", "#579337", "#629f3d", "#6eaa44")]
GRASS_SPECK_LIGHT = hexc("#82bb4e")
GRASS_SPECK_DARK = hexc("#437a2c")
GRASS_EDGE_DARK = hexc("#2f5a22")  # viền răng cưa cỏ (block: mép cỏ trên mặt cạnh)
DIRT_PALETTE = [hexc(c) for c in ("#ad6d3f", "#ba7a48", "#c68752", "#cf935d")]
DIRT_MARK_DARK = hexc("#6c3a21")   # vết sỏi/lõm tối 2–3 px
DIRT_MARK_MID = hexc("#8a5130")
DIRT_DOT_LIGHT = hexc("#e3ad78")   # chấm sáng thưa


def _ground_octaves(size: int) -> tuple[tuple[int, float], ...]:
    """Tần số theo mét (không theo pixel) để texture 1 m và 4 m cùng cỡ mảng màu."""
    m = max(1, size // PX_PER_M)
    return ((max(2, m), 0.55), (max(2, m * 2), 0.3), (m * 8, 0.15))


def _flat_fill(size: int, rng: random.Random, palette: list[tuple[int, int, int]], contrast: float, dither: float) -> Image.Image:
    n = fbm(size, rng, _ground_octaves(size))
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            v = (n[y][x] - 0.5) * contrast + 0.5
            px[x, y] = palette[quantize(v, x, y, len(palette), dither)]
    return img


def gen_grass_ground(size: int = 128, seed: int = 11) -> Image.Image:
    rng = random.Random(seed)
    img = _flat_fill(size, rng, GRASS_PALETTE, 1.5, 0.2)
    px = img.load()
    # Đốm thưa (~3/m²): sáng 1 px + tối 1 px bên dưới → gợi ngọn cỏ, không thành "sợi" dày
    for _ in range(size * size * 3 // (PX_PER_M * PX_PER_M)):
        x, y = rng.randrange(size), rng.randrange(size)
        px[x, y] = GRASS_SPECK_LIGHT
        px[x, (y + 1) % size] = GRASS_SPECK_DARK
    return img


def gen_dirt_ground(size: int = 128, seed: int = 23) -> Image.Image:
    rng = random.Random(seed)
    img = _flat_fill(size, rng, DIRT_PALETTE, 1.4, 0.2)
    px = img.load()
    # Vết tối ngắn 2–3 px (~4/m²), đôi khi gãy 1 px xuống → giống dấu sỏi/lõm trong ảnh mẫu
    for _ in range(size * size * 4 // (PX_PER_M * PX_PER_M)):
        x, y = rng.randrange(size), rng.randrange(size)
        length = rng.choice((2, 2, 3))
        for i in range(length):
            dy = 1 if (i == length - 1 and rng.random() < 0.35) else 0
            px[(x + i) % size, (y + dy) % size] = DIRT_MARK_DARK if i else DIRT_MARK_MID
    # Chấm sáng thưa (~1/m²)
    for _ in range(size * size // (PX_PER_M * PX_PER_M)):
        x, y = rng.randrange(size), rng.randrange(size)
        px[x, y] = DIRT_DOT_LIGHT
    return img


def gen_edge_fringe(size: int = 128, seed: int = 61) -> Image.Image:
    """Mặt nạ xám lát liền (32 px = 1 m) làm lệch ngưỡng đất/cỏ trong terrain_ground.gdshader → mép răng cưa.
    Răng 2–6 px (8–16 ô/m) + một lớp thấp (2 ô/m) để răng dài ngắn không đều."""
    rng = random.Random(seed)
    m = max(1, size // PX_PER_M)
    n = fbm(size, rng, ((m * 2, 0.3), (m * 8, 0.5), (m * 16, 0.2)))
    img = Image.new("L", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            px[x, y] = max(0, min(255, int(((n[y][x] - 0.5) * 2.6 + 0.5) * 255)))
    return img


# ---------------------------------------------------------------- Bụi cỏ cao (billboard)
TUFT_RAMP = [hexc(c) for c in ("#22401f", "#2f5726", "#41722e", "#558c36", "#6ca63f", "#8cbf4c", "#b0d463", "#d2e07e")]
SEED_HEAD = [hexc("#e6dc9a"), hexc("#c8b870")]
TUFT_W, TUFT_H, TUFT_VARIANTS = 32, 24, 6


def draw_blade(px, ox: int, base_x: float, height: int, lean: float, bright: float, seed_head: bool) -> None:
    """Lá cỏ cong từ gốc lên ngọn, tối → sáng theo chiều cao; có thể có bông cỏ ở ngọn."""
    last = None
    for i in range(height):
        t = i / max(1, height - 1)
        x = base_x + lean * t * t
        y = TUFT_H - 1 - i
        idx = min(len(TUFT_RAMP) - 1, int((t * 0.8 + bright * 0.35) * len(TUFT_RAMP)))
        xi = int(round(x))
        if 0 <= xi < TUFT_W:
            px[ox + xi, y] = TUFT_RAMP[idx] + (255,)
            last = (xi, y)
        if t < 0.3 and 0 <= xi + 1 < TUFT_W:  # gốc dày 2 px
            px[ox + xi + 1, y] = TUFT_RAMP[max(0, idx - 1)] + (255,)
    if seed_head and last:
        xi, y = last
        for k, dy in enumerate((0, 1, 2)):
            if 0 <= y + dy < TUFT_H:
                px[ox + xi, y + dy] = SEED_HEAD[k % 2] + (255,)


def gen_grass_tufts(seed: int = 5) -> Image.Image:
    rng = random.Random(seed)
    img = Image.new("RGBA", (TUFT_W * TUFT_VARIANTS, TUFT_H), (0, 0, 0, 0))
    px = img.load()
    for v in range(TUFT_VARIANTS):
        ox = v * TUFT_W
        blades = []
        spread = 4.0 + v % 3 * 1.2
        for _ in range(rng.randint(20, 27)):
            base = max(2.0, min(TUFT_W - 3.0, rng.gauss(TUFT_W / 2, spread)))
            center_bias = 1.0 - abs(base - TUFT_W / 2) / (TUFT_W / 2)
            height = min(TUFT_H, int(rng.uniform(7, 12) + center_bias * rng.uniform(5, 11)))
            lean = (base - TUFT_W / 2) * 0.6 + rng.uniform(-4.0, 4.0)
            seed_head = v >= 4 and rng.random() < 0.25
            blades.append((height, base, lean, rng.random(), seed_head))
        # Lá tối vẽ trước, lá sáng vẽ sau → khối cỏ có chiều sâu
        for height, base, lean, bright, seed_head in sorted(blades, key=lambda b: b[3]):
            draw_blade(px, ox, base, height, lean, bright, seed_head)
    return img


# ---------------------------------------------------------------- Hoa dại (billboard)
FLOWER_W = 16
STEM = (hexc("#3e6a2a"), hexc("#5d9136"))
FLOWER_COLORS = [  # (cánh sáng, cánh tối, nhụy)
    (hexc("#fbf6e8"), hexc("#cfc6d6"), hexc("#f2c94c")),
    (hexc("#ffd84a"), hexc("#d9a12c"), hexc("#a0522d")),
    (hexc("#f58fb0"), hexc("#c95a86"), hexc("#ffe9a8")),
    (hexc("#8fa6ff"), hexc("#5b6fd1"), hexc("#fff2b0")),
]


def gen_flowers(seed: int = 9) -> Image.Image:
    rng = random.Random(seed)
    img = Image.new("RGBA", (FLOWER_W * len(FLOWER_COLORS), FLOWER_W), (0, 0, 0, 0))
    px = img.load()
    for v, (light, dark, core) in enumerate(FLOWER_COLORS):
        ox = v * FLOWER_W
        heads = [(7, 4), (4, 8), (11, 7)] if v % 2 == 0 else [(8, 5), (5, 9)]
        for hx, hy in heads:
            # thân + 1 lá
            for y in range(hy + 2, FLOWER_W):
                px[ox + hx, y] = STEM[0] + (255,)
            leaf_y = rng.randint(hy + 4, FLOWER_W - 3)
            px[ox + hx + rng.choice((-1, 1)), leaf_y] = STEM[1] + (255,)
            # bông hình chữ thập 3x3 + nhụy
            for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
                px[ox + hx + dx, hy + dy] = (light if dy <= 0 else dark) + (255,)
            px[ox + hx, hy] = core + (255,)
    return img


# ---------------------------------------------------------------- Bố cục map
def rect_paint(px, x0: int, z0: int, x1: int, z1: int, color: tuple[int, int, int, int], size: int) -> None:
    """Tô hình chữ nhật theo tọa độ thế giới (m); map size x size, tâm ở gốc tọa độ."""
    half = size // 2
    for z in range(z0, z1):
        for x in range(x0, x1):
            ix, iz = x + half, z + half
            if 0 <= ix < size and 0 <= iz < size:
                px[ix, iz] = color


def gen_layout(size: int = 48, seed: int = 3) -> Image.Image:
    rng = random.Random(seed)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    px = img.load()
    n = fbm(size, rng, ((6, 0.7), (12, 0.3)))
    edge_noise = fbm(size, rng, ((8, 1.0),))
    for z in range(size):
        for x in range(size):
            # G: cỏ cao theo từng mảng, chừa khoảng trống cỏ ngắn
            g = 255 if n[z][x] > 0.45 else 0
            # A = 0: rừng bao quanh viền map (dày 4..7 ô, mép lượn theo noise)
            d = min(x, z, size - 1 - x, size - 1 - z)
            forest = d < 4 + edge_noise[z][x] * 3.5
            px[x, z] = (0, 0, 0, 0) if forest else (0, g, 0, 255)
    # R: đường đất hình chữ S rộng 3 ô, xuyên rừng ra 2 mép map (lối sang map khác sau này)
    path = [
        (-2, 2, 1, 24),      # đoạn nam (điểm spawn z = 10)
        (-2, -1, 9, 2),      # rẽ đông
        (6, -15, 9, 2),      # lên bắc
        (-8, -15, 9, -12),   # rẽ tây
        (-8, -24, -5, -12),  # ra mép bắc
    ]
    for x0, z0, x1, z1 in path:
        rect_paint(px, x0, z0, x1, z1, (255, 0, 0, 255), size)
    # B: hồ nước phía tây, ghép từ vài hình chữ nhật → mép bậc thang giống tile
    for x0, z0, x1, z1 in ((-15, 2, -8, 8), (-13, 0, -9, 2), (-17, 4, -15, 7), (-12, 8, -9, 9)):
        rect_paint(px, x0, z0, x1, z1, (0, 0, 255, 255), size)
    # Quanh điểm spawn: cỏ ngắn cho dễ nhìn nhân vật lúc vào map
    rect_paint(px, 1, 8, 4, 12, (0, 0, 0, 255), size)
    return img


# ---------------------------------------------------------------- Lá + vỏ cây (cho cây 3D stylized)
# Atlas lá: 4 cột x 2 hàng ô 32x32. Hàng 0 = chùm lá bản rộng, hàng 1 = chùm lá kim.
# Lưu dạng xám (độ sáng) – shader foliage_leaves tô màu theo bảng màu riêng mỗi loài.
LEAF_CELL = 32
LEAF_LEVELS = 6
BARK = [hexc(c) for c in ("#2a1a12", "#3f2819", "#5a3a24", "#77502f", "#93683d")]


def _put_gray(px, x: int, y: int, v: float) -> None:
    g = int(max(0.0, min(1.0, round(v * (LEAF_LEVELS - 1)) / (LEAF_LEVELS - 1))) * 255)
    px[x, y] = (g, g, g, 255)


def _leaf_clump(px, ox: int, oy: int, rng: random.Random) -> None:
    c = LEAF_CELL / 2
    leaves = []
    for _ in range(rng.randint(22, 28)):
        a = rng.uniform(0, math.tau)
        r = math.sqrt(rng.random()) * 9.5
        leaves.append((c + math.cos(a) * r, c + math.sin(a) * r * 0.9, rng.uniform(0, math.tau),
                       rng.uniform(3.8, 5.5), rng.uniform(1.8, 2.6), rng.uniform(0.35, 0.8)))
    leaves.sort(key=lambda l: l[1])  # lá phía dưới (y lớn) vẽ sau → che lá trên
    for lx, ly, ang, ln, wd, base in leaves:
        ca, sa = math.cos(ang), math.sin(ang)
        for y in range(int(ly - ln) - 1, int(ly + ln) + 2):
            for x in range(int(lx - ln) - 1, int(lx + ln) + 2):
                if not (0 <= x < LEAF_CELL and 0 <= y < LEAF_CELL):
                    continue
                dx, dy = x - lx, y - ly
                u = dx * ca + dy * sa
                v = -dx * sa + dy * ca
                if (u / ln) ** 2 + (v / wd) ** 2 > 1.0:
                    continue
                shade = base + 0.28 * (-(dx * -0.6 + dy * -0.8) / ln) * -1.0  # sáng phía trên-trái
                if abs(v) < 0.6:
                    shade -= 0.1  # gân lá
                _put_gray(px, ox + x, oy + y, shade)
    # Viền tối quanh chùm
    for y in range(LEAF_CELL):
        for x in range(LEAF_CELL):
            p = px[ox + x, oy + y]
            if p[3] == 0:
                continue
            edge = any(not (0 <= x + dx < LEAF_CELL and 0 <= y + dy < LEAF_CELL) or px[ox + x + dx, oy + y + dy][3] == 0
                       for dx, dy in ((1, 0), (0, 1)))
            if edge:
                _put_gray(px, ox + x, oy + y, p[0] / 255 - 0.25)


def _needle_clump(px, ox: int, oy: int, rng: random.Random) -> None:
    """Chùm lá kim dày: lõi đặc hình quạt + kim tỏa ra rủ xuống, sáng phía trên-trái, viền dưới tối."""
    c = LEAF_CELL / 2
    # Lõi: elip dẹt hơi lệch lên, che kín để không nhìn xuyên thấy thân cây
    for y in range(LEAF_CELL):
        for x in range(LEAF_CELL):
            dx, dy = (x - c) / 9.5, (y - c - 1) / 6.5
            if dx * dx + dy * dy <= 1.0 + rng.uniform(-0.15, 0.15):
                _put_gray(px, ox + x, oy + y, 0.4 - dy * 0.15 - dx * 0.05 + rng.uniform(-0.08, 0.08))
    for _ in range(rng.randint(110, 130)):
        a = rng.uniform(math.pi * 1.05, math.pi * 1.95) if rng.random() < 0.3 else rng.uniform(-0.2, math.pi + 0.2)
        length = rng.uniform(6, 13)
        sx, sy = c + rng.uniform(-6, 6), c + rng.uniform(-3, 2)
        base = rng.uniform(0.4, 0.8)
        for i in range(int(length)):
            t = i / length
            x = int(round(sx + math.cos(a) * i))
            y = int(round(sy + math.sin(a) * i * 0.6 + t * t * 3.0))  # rủ xuống
            if 0 <= x < LEAF_CELL and 0 <= y < LEAF_CELL:
                _put_gray(px, ox + x, oy + y, base + 0.2 * (1 - t) - 0.2 * max(0.0, math.sin(a)) - (x - c) * 0.01)
    # Viền dưới tối → từng chùm (và tầng thông) tách khối
    for x in range(LEAF_CELL):
        for y in range(LEAF_CELL - 1, -1, -1):
            p = px[ox + x, oy + y]
            if p[3] != 0:
                _put_gray(px, ox + x, oy + y, p[0] / 255 - 0.25)
                break


def gen_leaf_atlas(seed: int = 31) -> Image.Image:
    rng = random.Random(seed)
    img = Image.new("RGBA", (LEAF_CELL * 4, LEAF_CELL * 2), (0, 0, 0, 0))
    px = img.load()
    for i in range(4):
        _leaf_clump(px, i * LEAF_CELL, 0, rng)
        _needle_clump(px, i * LEAF_CELL, LEAF_CELL, rng)
    return img


def gen_bark(seed: int = 41) -> Image.Image:
    """Vỏ cây 16x32, lát liền theo chiều dọc: sọc dọc + vết nứt."""
    rng = random.Random(seed)
    w, h = 16, 32
    img = Image.new("RGB", (w, h))
    px = img.load()
    cols = [rng.choice((1, 2, 2, 3, 3, 4)) for _ in range(w)]
    for x in range(w):
        for y in range(h):
            idx = cols[x]
            if rng.random() < 0.15:
                idx = max(0, min(4, idx + rng.choice((-1, 1))))
            px[x, y] = BARK[idx]
    for _ in range(6):  # vết nứt dọc
        x, y0, ln = rng.randrange(w), rng.randrange(h), rng.randint(4, 10)
        for i in range(ln):
            px[x, (y0 + i) % h] = BARK[0]
    return img


def main() -> None:
    TERRAIN_DIR.mkdir(parents=True, exist_ok=True)
    TREE_DIR.mkdir(parents=True, exist_ok=True)
    gen_grass_ground().save(TERRAIN_DIR / "grass_ground.png")
    gen_dirt_ground().save(TERRAIN_DIR / "dirt_ground.png")
    gen_edge_fringe().save(TERRAIN_DIR / "edge_fringe.png")
    gen_grass_tufts().save(TERRAIN_DIR / "grass_tufts.png")
    gen_flowers().save(TERRAIN_DIR / "flowers.png")
    gen_leaf_atlas().save(TREE_DIR / "leaves.png")
    gen_bark().save(TREE_DIR / "bark.png")
    gen_layout().save(LEVEL_DIR / "meadow_road_layout.png")
    print("OK ->", TERRAIN_DIR, TREE_DIR, LEVEL_DIR)


if __name__ == "__main__":
    main()
