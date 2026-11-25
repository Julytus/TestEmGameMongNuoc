"""Sinh sprite sheet nhân vật chính (cô cung thủ chibi) bằng PIL.

Nhân vật được "rig" bằng các khối hình (tóc, mặt, áo, chân, khăn, cung) vẽ theo thứ tự sau → trước,
mỗi khối tô bóng theo pháp tuyến giả (đèn trên-trái) rồi lượng tử về bảng màu cố định.
Hậu kỳ: bóng đổ (AO) dưới khối đứng trước + viền ngoài tối theo màu vật liệu bên cạnh.

Đầu ra:
  assets/art/characters/player/heroine_sheet.png   (khung 32x32, mỗi hàng = 1 animation_hướng)
  src/entities/player/heroine_frames.tres           (SpriteFrames dùng AtlasTexture trỏ vào sheet)

Chạy:  python tools/art/gen_character.py [--preview out.png]
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SHEET_PATH = ROOT / "assets/art/characters/player/heroine_sheet.png"
FRAMES_PATH = ROOT / "src/entities/player/heroine_frames.tres"
SHEET_RES = "res://assets/art/characters/player/heroine_sheet.png"

W = H = 32

# ------------------------------------------------------------------ Bảng màu
# ramp: sáng → tối; outline: màu viền ngoài khi giáp vật liệu này
PAL: dict[str, tuple[list[tuple[int, int, int]], tuple[int, int, int]]] = {
	"hair": ([(255, 251, 242), (238, 230, 216), (208, 198, 190), (166, 154, 162), (120, 108, 128)], (62, 50, 72)),
	"skin": ([(255, 234, 214), (247, 204, 176), (220, 156, 136), (176, 112, 106)], (98, 52, 58)),
	"coat": ([(172, 74, 74), (132, 48, 58), (96, 34, 50), (66, 26, 42)], (34, 16, 28)),
	"scarf": ([(255, 112, 92), (226, 64, 58), (174, 38, 50), (124, 28, 46)], (66, 16, 30)),
	"legs": ([(96, 84, 106), (70, 60, 82), (48, 42, 60)], (24, 20, 32)),
	"boots": ([(180, 116, 72), (140, 84, 54), (100, 60, 44), (72, 42, 36)], (42, 24, 22)),
	"wood": ([(214, 152, 86), (170, 106, 58), (124, 74, 44)], (58, 32, 24)),
	"gold": ([(255, 230, 140), (226, 176, 82), (172, 122, 62)], (70, 44, 26)),
	"string": ([(240, 232, 214), (200, 190, 176)], (90, 80, 80)),
	"smear": ([(255, 255, 250), (220, 238, 246), (180, 214, 232)], (0, 0, 0)),
}
RAW = {
	"eye_dark": (44, 30, 58),
	"eye_iris": (72, 120, 196),
	"eye_low": (120, 190, 236),
	"eye_glint": (255, 255, 255),
	"mouth": (176, 92, 96),
	"blush": (244, 166, 160),
}
LIGHT = (-0.45, -0.6, 0.66)
_ln = math.sqrt(sum(v * v for v in LIGHT))
LIGHT = tuple(v / _ln for v in LIGHT)


class Canvas:
	def __init__(self) -> None:
		self.mat: list[list[str | None]] = [[None] * W for _ in range(H)]
		self.lvl = [[0] * W for _ in range(H)]
		self.z = [[-1] * W for _ in range(H)]
		self.no_ao = [[False] * W for _ in range(H)]
		self.zc = 0

	def inside(self, x: int, y: int) -> bool:
		return 0 <= x < W and 0 <= y < H

	def put(self, x: float, y: float, mat: str, lvl: int = 0, z: int | None = None, ao: bool = True) -> None:
		x, y = int(math.floor(x)), int(math.floor(y))
		if not self.inside(x, y):
			return
		self.mat[y][x] = mat
		self.lvl[y][x] = lvl
		self.z[y][x] = self.zc if z is None else z
		self.no_ao[y][x] = not ao

	def part(self, mask, mat: str, shade, lvl_bias: int = 0, ao: bool = True) -> None:
		"""Vẽ một khối: mask(x, y) -> bool, shade(x, y) -> độ sáng [-1, 1]."""
		self.zc += 1
		n = len(PAL[mat][0])
		for y in range(H):
			for x in range(W):
				if mask(x, y):
					b = shade(x, y)
					self.put(x, y, mat, max(0, min(n - 1, quantize(b, n) + lvl_bias)), ao=ao)

	def erase(self, x: int, y: int) -> None:
		if self.inside(x, y):
			self.mat[y][x] = None
			self.z[y][x] = -1

	def render(self) -> Image.Image:
		# AO: pixel nằm ngay dưới một khối khác vẽ sau (đứng trước) → tối hơn 1 bậc
		lvl = [row[:] for row in self.lvl]
		for y in range(1, H):
			for x in range(W):
				m = self.mat[y][x]
				if m is None or m in RAW or self.no_ao[y][x]:
					continue
				above = self.mat[y - 1][x]
				if above is not None and self.z[y - 1][x] > self.z[y][x] and above != m and above not in RAW:
					lvl[y][x] = min(len(PAL[m][0]) - 1, lvl[y][x] + 1)
		img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
		px = img.load()
		for y in range(H):
			for x in range(W):
				m = self.mat[y][x]
				if m is None:
					continue
				px[x, y] = (*(RAW[m] if m in RAW else PAL[m][0][lvl[y][x]]), 255)
		# Viền ngoài
		out = img.copy()
		po = out.load()
		for y in range(H):
			for x in range(W):
				if self.mat[y][x] is not None:
					continue
				best = None
				for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
					nx, ny = x + dx, y + dy
					if self.inside(nx, ny) and self.mat[ny][nx] is not None:
						m = self.mat[ny][nx]
						if m == "smear":
							continue
						col = (40, 26, 40) if m in RAW else PAL[m][1]
						# ưu tiên viền của pixel bên trên (đầu/tóc) cho gọn
						if best is None or dy == 1:
							best = col
				if best is not None:
					po[x, y] = (*best, 255)
		return out


def quantize(b: float, n: int) -> int:
	# b ∈ [-1, 1]: 1 = hướng thẳng về đèn
	cuts = {2: [0.35], 3: [0.62, 0.25], 4: [0.74, 0.46, 0.12], 5: [0.8, 0.58, 0.32, 0.02]}[n]
	for i, c in enumerate(cuts):
		if b > c:
			return i
	return n - 1


def sphere(cx: float, cy: float, rx: float, ry: float, flat: float = 0.0):
	def f(x: int, y: int) -> float:
		nx = (x + 0.5 - cx) / rx
		ny = (y + 0.5 - cy) / ry
		nz = math.sqrt(max(0.0, 1.0 - nx * nx - ny * ny))
		nx, ny = nx * (1 - flat), ny * (1 - flat)
		return nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]
	return f


def cylinder(cx: float, rx: float, top: float = 0.0, slope: float = 0.0):
	"""Trụ đứng: sáng theo trục x, tối dần xuống dưới (slope / px)."""
	def f(x: int, y: int) -> float:
		nx = max(-1.0, min(1.0, (x + 0.5 - cx) / rx))
		nz = math.sqrt(max(0.0, 1.0 - nx * nx))
		return nx * LIGHT[0] + nz * LIGHT[2] + top - slope * y
	return f


def ellipse(cx: float, cy: float, rx: float, ry: float):
	return lambda x, y: ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0


def rows(spans: dict[int, tuple[int, int]]):
	return lambda x, y: y in spans and spans[y][0] <= x <= spans[y][1]


def union(*masks):
	return lambda x, y: any(m(x, y) for m in masks)


def minus(a, b):
	return lambda x, y: a(x, y) and not b(x, y)


# ------------------------------------------------------------------ Khối dùng chung

def hair_head(cx: float, cy: float):
	"""Khối tóc đầu: tối hơn cầu thường + lọn tóc (vệt tối chéo) cho đỡ phẳng."""
	base = sphere(cx - 1.5, cy - 2.0, 8.0, 8.0, 0.25)
	def f(x: int, y: int) -> float:
		b = base(x, y) + 0.02
		# sợi tóc mảnh toả từ xoáy (hơi lệch trái trên đỉnh)
		ang = math.atan2(y + 0.5 - (cy - 6.5), x + 0.5 - (cx - 1))
		fr = (ang * 2.6) % 1.0
		if abs(fr - 0.5) < 0.09 and y > cy - 5:
			b -= 0.25
		return b
	return f


def flat_skin(cx: float, cy: float, rx: float, ry: float, side: bool = False):
	"""Da kiểu anime: phẳng, chỉ một bậc tối ở mép phải (hoặc cằm khi nhìn ngang)."""
	def f(x: int, y: int) -> float:
		if not side and x + 0.5 > cx + rx - 1.6:
			return 0.5
		if y + 0.5 > cy + ry - 1.2:
			return 0.5
		return 0.9
	return f


def hair_clumps(base, sway_fn, start_y: int):
	"""Tóc dài: các lọn (sóng sin theo cột) + sợi tối, đuôi tóc tối dần."""
	def f(x: int, y: int) -> float:
		b = base(x, y)
		if y >= start_y:
			sx = x - sway_fn(y)
			b -= 0.22 * (0.5 + 0.5 * math.sin(sx * 2.09 + 0.6))
			if sx % 3 == 1:
				b -= 0.12
		return b
	return f


def highlight_band(c: "Canvas", cx: float, cy: float, r: float, x0: int, x1: int) -> None:
	"""Vòng sáng (angel ring) cong theo đầu."""
	for x in range(x0, x1 + 1):
		if (x - x0) % 4 == 3:
			continue
		dx = (x + 0.5 - cx) / r
		y = int(math.floor(cy - r * 0.5 + 3.2 * dx * dx))
		if c.inside(x, y) and c.mat[y][x] == "hair":
			c.lvl[y][x] = 0
			if c.inside(x, y + 1) and c.mat[y + 1][x] == "hair":
				c.lvl[y + 1][x] = min(c.lvl[y + 1][x], 1)


def ahoge(c: "Canvas", x: int, y: int, d: int = 1) -> None:
	c.zc += 1
	c.put(x, y, "hair", 1)
	c.put(x + d, y - 1, "hair", 0)
	c.put(x + 2 * d, y - 1, "hair", 1)

def hair_strands(base, sway_fn, start_y: int, period: int = 3, phase: int = 0):
	"""Thêm sợi tóc tối theo cột + đuôi tóc tối hơn."""
	def f(x: int, y: int) -> float:
		b = base(x, y)
		if y >= start_y:
			sx = x - sway_fn(y)
			if (sx + phase) % period == 0:
				b -= 0.3
		return b
	return f


def draw_boot(c: Canvas, x0: int, y_top: int, width: int, toe: int, lift: int, far: bool) -> None:
	"""Chân: tất tối 2 hàng + ủng 3 hàng; toe: số pixel mũi ủng nhô (hướng ngang)."""
	y = y_top - lift
	bias = 1 if far else 0
	c.part(rows({y: (x0, x0 + width - 1), y + 1: (x0, x0 + width - 1)}), "legs",
			cylinder(x0 + width / 2, width / 2 + 0.5), bias)
	spans = {y + 2: (x0, x0 + width - 1), y + 3: (x0, x0 + width - 1), y + 4: (x0, x0 + width - 1 + toe)}
	if lift == 0:
		spans = {k: v for k, v in spans.items()}
	c.part(rows(spans), "boots", cylinder(x0 + width / 2 + toe / 2, width / 2 + 1, 0.1, 0.0), bias)
	# đế ủng tối
	for x in range(x0, x0 + width + toe):
		if c.mat[min(H - 1, y + 4)][x] == "boots":
			c.lvl[y + 4][x] = min(3, c.lvl[y + 4][x] + 1)


def draw_bow(c: Canvas, x: float, y0: int, y1: int, bulge: float, facing: int = 1, string_pull: float = 0.0) -> None:
	"""Cung đứng: thân cong (bulge px) về phía `facing`, dây thẳng (hoặc kéo về sau)."""
	c.zc += 1
	length = y1 - y0
	mid = (y0 + y1) / 2
	for y in range(y0, y1 + 1):
		t = (y - y0) / max(1, length)
		off = bulge * math.sin(math.pi * t)
		bx = x + off * facing
		lvl = 0 if y < mid else 1
		if y in (y0, y1):
			c.put(bx, y, "gold", 1)
		else:
			c.put(bx, y, "wood", lvl)
		# dây
		sp = string_pull * math.sin(math.pi * t)
		sx = x - facing * (0.0 + sp)
		if y not in (y0, y1) and int(math.floor(sx)) != int(math.floor(bx)):
			c.put(sx, y, "string", 0, ao=False)


# ------------------------------------------------------------------ Hướng trước (down)

def draw_front(p: dict) -> Canvas:
	c = Canvas()
	bob = p.get("bob", 0)
	sway = p.get("sway", 0)
	hy = 10.5 + bob + p.get("head_dy", 0)

	def sway_fn(y: int) -> int:
		return int(round(sway * max(0, (y - 15)) / 10.0))

	# Tóc dài phía sau
	back_spans = {}
	for y in range(int(hy) - 2, 28 + bob):
		w = 7.6 + min(1.6, max(0, y - hy - 4) * 0.25)
		s = sway_fn(y)
		back_spans[y] = (int(round(15.5 - w)) + s, int(round(15.5 + w)) - 1 + s)
	# đuôi tóc nhọn
	tips = {}
	for x in range(0, W):
		tips[x] = 25 + bob + (0, 1, 2, 1)[x % 4]
	back = lambda x, y: y in back_spans and back_spans[y][0] <= x <= back_spans[y][1] and y <= tips[x - sway_fn(y)] if 0 <= x - sway_fn(y) < W else False
	c.part(back, "hair", hair_clumps(cylinder(15.5, 9, -0.05, 0.01), sway_fn, 15), 1)

	# Chân + ủng
	ll, rl = p.get("lift_l", 0), p.get("lift_r", 0)
	draw_boot(c, 12, 26, 3, 0, ll, False)
	draw_boot(c, 17, 26, 3, 0, rl, False)

	# Áo khoác (thân + vạt xòe)
	coat = {}
	for y in range(18 + bob, 26 + bob):
		k = y - (18 + bob)
		half = 4.5 if k < 4 else 4.5 + (k - 3) * 0.5
		coat[y] = (int(round(15.5 - half)), int(round(15.5 + half)) - 1)
	c.part(rows(coat), "coat", cylinder(15.5, 6, 0.05, 0.0))
	# viền vàng + nẹp giữa
	c.zc += 1
	for y in range(20 + bob, 26 + bob):
		c.put(15, y, "coat", 3)
	c.put(16, 22 + bob, "gold", 1)
	c.put(15, 22 + bob, "gold", 0)
	for x in range(coat[25 + bob][0], coat[25 + bob][1] + 1):
		c.put(x, 25 + bob, "gold", 1 if x < 16 else 2)
	# thắt lưng
	for x in range(11, 21):
		if c.mat[22 + bob][x] == "coat":
			c.put(x, 22 + bob, "boots", 2)
	c.put(15, 22 + bob, "gold", 0)
	c.put(16, 22 + bob, "gold", 1)

	# Tay
	arm_l = p.get("arm_l", 0)
	arm_r = p.get("arm_r", 0)
	c.part(rows({y: (9, 10) for y in range(19 + bob + arm_l, 23 + bob + arm_l)}), "coat", cylinder(10, 2), 1)
	c.part(rows({y: (21, 22) for y in range(19 + bob + arm_r, 23 + bob + arm_r)}), "coat", cylinder(22, 2), 1)
	c.part(rows({23 + bob + arm_l: (9, 10)}), "skin", lambda x, y: 0.5)
	c.part(rows({23 + bob + arm_r: (21, 22)}), "skin", lambda x, y: 0.3)

	# Cung trong tay phải (bên phải màn hình)
	if p.get("bow", True):
		draw_bow(c, 23.5, 15 + bob + arm_r, 29 + bob + arm_r, 1.6, 1)
		c.part(rows({23 + bob + arm_r: (21, 23)}), "skin", lambda x, y: 0.3)

	# Khăn quàng
	flap = p.get("scarf", 0)
	scarf = {18 + bob: (11, 20), 19 + bob: (12, 19)}
	c.part(rows(scarf), "scarf", cylinder(15.5, 5, 0.1, 0.0))
	tail = {}
	for i, y in enumerate(range(19 + bob, 24 + bob)):
		dx = int(round(flap * i / 4))
		tail[y] = (12 - dx, 13 - dx) if i < 4 else (12 - dx, 12 - dx)
	c.part(rows(tail), "scarf", cylinder(12.5, 2, -0.1), 0)

	# Đầu: khối tóc
	head = ellipse(15.5, hy, 7.9, 7.4)
	c.part(head, "hair", hair_head(15.5, hy))
	# Mặt
	face = ellipse(15.5, hy + 2.7, 5.9, 4.7)
	c.part(face, "skin", flat_skin(15.5, hy + 2.7, 5.9, 4.7))
	# Mái tóc răng cưa che trán
	bang_base = int(hy) + 0
	pattern = (2, 1, 0, 1, 2, 2, 1, 0, 0, 1, 2, 2, 1, 0, 1, 2)
	bangs = lambda x, y: head(x, y) and 8 <= x <= 23 and y <= bang_base + pattern[(x - 8) % 16] - 0
	c.part(bangs, "hair", hair_head(15.5, hy))
	# Tóc mai hai bên mặt (mảnh, dài xuống vai)
	c.part(rows({y: (9, 9 if y > int(hy) + 2 else 10) for y in range(int(hy), int(hy) + 9)}), "hair", cylinder(9.5, 2.5, 0.0), 0)
	c.part(rows({y: (22 if y > int(hy) + 2 else 21, 22) for y in range(int(hy), int(hy) + 9)}), "hair", cylinder(22, 2.5, 0.0), 1)
	highlight_band(c, 15.5, hy, 7.4, 10, 18)

	# Mắt
	ey = int(hy) + 2
	if p.get("blink"):
		for ex in (12, 18):
			c.put(ex, ey + 1, "eye_dark")
			c.put(ex + 1, ey + 1, "eye_dark")
	elif p.get("pain"):
		for ex, d in ((12, 1), (18, -1)):
			c.put(ex, ey, "eye_dark")
			c.put(ex + 1, ey + 1, "eye_dark") if d == 1 else c.put(ex, ey + 1, "eye_dark")
			c.put(ex, ey + 2, "eye_dark") if d == 1 else c.put(ex + 1, ey, "eye_dark")
	else:
		for ex in (12, 18):
			c.put(ex, ey, "eye_dark")
			c.put(ex + 1, ey, "eye_dark")
			c.put(ex, ey + 1, "eye_iris")
			c.put(ex + 1, ey + 1, "eye_glint")
			c.put(ex, ey + 2, "eye_low")
			c.put(ex + 1, ey + 2, "eye_iris")
	c.put(11, ey + 3, "blush")
	c.put(20, ey + 3, "blush")
	c.put(15, ey + 3, "mouth") if not p.get("pain") else c.put(15, ey + 3, "eye_dark")
	return c


# ------------------------------------------------------------------ Hướng sau (up)

def draw_back(p: dict) -> Canvas:
	c = Canvas()
	bob = p.get("bob", 0)
	sway = p.get("sway", 0)
	hy = 10.5 + bob + p.get("head_dy", 0)

	def sway_fn(y: int) -> int:
		return int(round(sway * max(0, (y - 15)) / 10.0))

	ll, rl = p.get("lift_l", 0), p.get("lift_r", 0)
	draw_boot(c, 12, 26, 3, 0, ll, False)
	draw_boot(c, 17, 26, 3, 0, rl, False)
	coat = {}
	for y in range(18 + bob, 26 + bob):
		k = y - (18 + bob)
		half = 4.5 if k < 4 else 4.5 + (k - 3) * 0.5
		coat[y] = (int(round(15.5 - half)), int(round(15.5 + half)) - 1)
	c.part(rows(coat), "coat", cylinder(15.5, 6, -0.05))
	for x in range(coat[25 + bob][0], coat[25 + bob][1] + 1):
		c.put(x, 25 + bob, "gold", 2)
	arm_l = p.get("arm_l", 0)
	arm_r = p.get("arm_r", 0)
	c.part(rows({y: (9, 10) for y in range(19 + bob + arm_l, 23 + bob + arm_l)}), "coat", cylinder(10, 2), 1)
	c.part(rows({y: (21, 22) for y in range(19 + bob + arm_r, 23 + bob + arm_r)}), "coat", cylinder(22, 2), 1)
	c.part(rows({23 + bob + arm_l: (9, 10)}), "skin", lambda x, y: 0.4)
	c.part(rows({23 + bob + arm_r: (21, 22)}), "skin", lambda x, y: 0.2)
	if p.get("bow", True):
		draw_bow(c, 8.0, 15 + bob + arm_l, 29 + bob + arm_l, 1.6, -1)
		c.part(rows({23 + bob + arm_l: (8, 10)}), "skin", lambda x, y: 0.4)
	# khăn: chỉ lộ đuôi bay
	flap = p.get("scarf", 0)
	tail = {}
	for i, y in enumerate(range(18 + bob, 23 + bob)):
		dx = int(round(flap * i / 4))
		tail[y] = (20 + dx, 21 + dx) if i < 4 else (21 + dx, 21 + dx)
	c.part(rows(tail), "scarf", cylinder(20.5, 2, -0.1))
	c.part(rows({17 + bob: (11, 20), 18 + bob: (11, 20)}), "scarf", cylinder(15.5, 5, -0.05))

	# Tóc dài phủ lưng (trước thân khi nhìn từ sau)
	back_spans = {}
	for y in range(int(hy) - 2, 28 + bob):
		w = 7.6 + min(1.2, max(0, y - hy - 4) * 0.2)
		if y > hy + 8:
			w -= min(2.2, (y - hy - 8) * 0.3)
		s = sway_fn(y)
		back_spans[y] = (int(round(15.5 - w)) + s, int(round(15.5 + w)) - 1 + s)
	tips = {x: 25 + bob + (0, 1, 2, 1)[x % 4] for x in range(W)}
	back = lambda x, y: (y in back_spans and back_spans[y][0] <= x <= back_spans[y][1]
			and 0 <= x - sway_fn(y) < W and y <= tips[x - sway_fn(y)])
	c.part(back, "hair", hair_clumps(cylinder(15.5, 9, 0.0, 0.012), sway_fn, 12))
	head = ellipse(15.5, hy, 7.9, 7.4)
	c.part(head, "hair", hair_head(15.5, hy))
	# bóng gáy dưới khối đầu
	for x in range(W):
		for y in range(int(hy) + 6, int(hy) + 9):
			if c.mat[y][x] == "hair" and not head(x, y) and head(x, y - 2):
				c.lvl[y][x] = min(4, c.lvl[y][x] + 1)
	highlight_band(c, 15.5, hy, 7.4, 9, 21)
	return c


# ------------------------------------------------------------------ Hướng ngang (side, nhìn sang phải)

def draw_side(p: dict) -> Canvas:
	"""Nhìn ngang sang phải. Mặt nằm gọn trong khối đầu (không lồi ra) để viền sạch;
	cung cầm phía trước người, không cắt qua mặt/thân; tóc dài gọn sau lưng."""
	c = Canvas()
	bob = p.get("bob", 0)
	sway = p.get("sway", 0)
	lean = p.get("lean", 0)
	hx = 15 + lean  # tâm đầu (int)
	hy = 10.5 + bob + p.get("head_dy", 0)
	iy = int(hy)

	def stream(y: int) -> int:
		# tóc bay về phía sau (trái), mạnh dần xuống đuôi
		return -int(round(sway * max(0, (y - 13)) / 12.0))

	# Tóc dài phía sau: từ gáy rủ xuống sau lưng, đuôi nhọn
	back_spans = {}
	for y in range(iy, 27 + bob):
		k = y - hy
		left = hx - 6.5 - min(1.5, max(0.0, k - 3) * 0.25)
		right = hx - 1 - max(0.0, k - 8) * 0.3
		s = stream(y)
		back_spans[y] = (int(round(left)) + s, int(round(right)) + s // 2)
	tips = {x: 24 + bob + (0, 1, 2, 1)[x % 4] for x in range(-10, W)}
	back = lambda x, y: (y in back_spans and back_spans[y][0] <= x <= back_spans[y][1]
			and -10 <= x - stream(y) < W and y <= tips[x - stream(y)])
	c.part(back, "hair", hair_clumps(cylinder(hx - 4, 5, 0.05, 0.01), stream, 14), 1)

	# Đuôi khăn bay sau lưng
	flap = p.get("scarf", 0)
	tail = {}
	for i, y in enumerate(range(18 + bob, 22 + bob)):
		x1 = hx - 3 - i - flap
		tail[y] = (x1 - 1, x1)
	c.part(rows(tail), "scarf", cylinder(hx - 4, 3, -0.1))

	# Chân xa (tối) → áo → chân gần
	near, far = p.get("near", 0), p.get("far", 0)
	draw_boot(c, hx - 2 + far, 26, 3, 1, p.get("lift_far", 0), True)
	draw_boot(c, hx - 1 + near, 26, 3, 1, p.get("lift_near", 0), False)
	coat = {}
	for y in range(18 + bob, 26 + bob):
		k = y - (18 + bob)
		coat[y] = (hx - 3 - (1 if k >= 5 else 0), hx + 3 + (1 if k >= 6 else 0))
	c.part(rows(coat), "coat", cylinder(hx + 0.5, 4.5, 0.05))
	for x in range(coat[25 + bob][0], coat[25 + bob][1] + 1):
		c.put(x, 25 + bob, "gold", 1)
	for x in range(coat[22 + bob][0], coat[22 + bob][1] + 1):
		c.put(x, 22 + bob, "boots", 2)
	# hàng khuy trước ngực
	c.put(hx + 3, 20 + bob, "gold", 1)
	c.put(hx + 3, 23 + bob, "gold", 2)

	# Khăn quanh cổ
	c.part(rows({17 + bob: (hx - 2, hx + 3), 18 + bob: (hx - 3, hx + 3)}), "scarf", cylinder(hx + 1, 4, 0.1))

	# Đầu
	head = ellipse(hx + 0.5, hy, 7.4, 7.2)
	c.part(head, "hair", hair_head(hx, hy))
	# Mặt: nửa trước của khối đầu, dưới mái
	face = lambda x, y: head(x, y) and x >= hx + 2 and y >= iy and ellipse(hx + 0.5, hy + 0.3, 7.4, 7.2)(x, y)
	c.part(face, "skin", flat_skin(hx + 4.5, hy + 2.6, 4.0, 4.6, True))
	pattern = (0, 1, 2, 1, 0, 1)
	bang = lambda x, y: head(x, y) and x >= hx + 1 and y <= iy + pattern[(x - hx) % 6]
	c.part(bang, "hair", hair_head(hx, hy))
	# tóc mai che tai, tối hơn để tách mặt khỏi tóc sau
	c.part(rows({y: (hx + 1, hx + 2 if y < iy + 4 else hx + 1) for y in range(iy, iy + 7)}), "hair",
			cylinder(hx + 1, 3, -0.2), 1)
	highlight_band(c, hx - 1, hy, 7.2, hx - 5, hx + 3)

	# Mắt + má + miệng
	ex, ey = hx + 4, iy + 2
	if p.get("pain"):
		c.put(ex, ey, "eye_dark")
		c.put(ex + 1, ey + 1, "eye_dark")
		c.put(ex, ey + 2, "eye_dark")
	elif p.get("blink"):
		c.put(ex, ey + 1, "eye_dark")
		c.put(ex + 1, ey + 1, "eye_dark")
	else:
		c.put(ex, ey, "eye_dark")
		c.put(ex + 1, ey, "eye_dark")
		c.put(ex, ey + 1, "eye_iris")
		c.put(ex + 1, ey + 1, "eye_glint")
		c.put(ex, ey + 2, "eye_low")
		c.put(ex + 1, ey + 2, "eye_iris")
	c.put(ex - 1, ey + 3, "blush")
	c.put(ex + 2, ey + 4, "mouth")

	# Tay gần + cung phía trước người
	arm = p.get("arm", "down")
	if arm == "down":
		c.part(rows({y: (hx, hx + 1) for y in range(19 + bob, 23 + bob)}), "coat", cylinder(hx + 1, 2), 1)
		if p.get("bow", True):
			draw_bow(c, hx + 5.5, 18 + bob, 29 + bob, 1.3, 1)
			c.part(rows({23 + bob: (hx + 1, hx + 5)}), "coat", cylinder(hx + 3, 3), 1)
			c.part(rows({23 + bob: (hx + 5, hx + 6)}), "skin", lambda x, y: 0.5)
		else:
			c.part(rows({23 + bob: (hx, hx + 1)}), "skin", lambda x, y: 0.5)
	else:
		draw_side_attack(c, p, hx, bob)
	return c


def draw_side_attack(c: Canvas, p: dict, hx: float, bob: int) -> None:
	"""Tay vung cung: arm = 'up' (giơ sau đầu), 'swing' (ngang trước), 'low' (chúc xuống trước)."""
	arm = p["arm"]
	ax, ay = int(hx) + 1, 19 + bob
	if arm == "up":
		c.part(rows({ay - 1: (ax - 1, ax), ay: (ax - 1, ax), ay + 1: (ax, ax)}), "coat", cylinder(ax, 2))
		c.part(rows({ay - 2: (ax - 2, ax - 1)}), "skin", lambda x, y: 0.5)
		# cung nằm chéo sau đầu
		for i in range(12):
			x = ax - 2 - i * 0.55
			y = ay - 3 - i * 0.6 + 0.08 * (i - 6) ** 2 - 2.0
			c.put(x, y, "wood" if 0 < i < 11 else "gold", 0 if i < 6 else 1)
	elif arm == "swing":
		c.part(rows({ay + 1: (ax, ax + 3), ay + 2: (ax, ax + 3)}), "coat", cylinder(ax + 2, 3))
		c.part(rows({ay + 1: (ax + 4, ax + 5), ay + 2: (ax + 4, ax + 5)}), "skin", lambda x, y: 0.5)
		for i in range(13):
			y = ay - 5 + i
			x = ax + 6 + 1.6 * math.sin(math.pi * i / 12)
			c.put(x, y, "wood" if 0 < i < 12 else "gold", 0 if i < 6 else 1)
	else:  # low
		c.part(rows({ay + 2: (ax, ax + 2), ay + 3: (ax + 1, ax + 3)}), "coat", cylinder(ax + 2, 3))
		c.part(rows({ay + 4: (ax + 3, ax + 4)}), "skin", lambda x, y: 0.5)
		for i in range(12):
			x = ax + 4 + i * 0.6
			y = ay + 5 - i * 0.15 + 0.07 * (i - 6) ** 2 - 2.5
			c.put(x, y, "wood" if 0 < i < 11 else "gold", 0 if i < 6 else 1)
	smear = p.get("smear")
	if smear:
		c.zc += 1
		cx, cy = hx, 19 + bob
		a0, a1 = smear
		for r, lv in ((11.5, 0), (10.5, 1), (9.5, 2)):
			for k in range(40):
				a = a0 + (a1 - a0) * k / 39
				x = cx + math.cos(a) * r
				y = cy + math.sin(a) * r * 0.8
				ix, iy = int(math.floor(x)), int(math.floor(y))
				if c.inside(ix, iy) and c.mat[iy][ix] is None:
					c.put(x, y, "smear", lv, ao=False)


# ------------------------------------------------------------------ Tấn công / lướt hướng trước & sau

def front_attack(p: dict, back: bool) -> Canvas:
	q = dict(p)
	q["bow"] = False
	c = draw_back(q) if back else draw_front(q)
	bob = p.get("bob", 0)
	stage = p["stage"]
	c.zc += 1
	if stage == "up":
		# cung giơ chéo bên phải trên đầu
		for i in range(13):
			x = 21 + i * 0.6
			y = 3 + i * 0.95 + 0.06 * (i - 6) ** 2
			c.put(x, y, "wood" if 0 < i < 12 else "gold", 0 if i < 6 else 1)
	elif stage == "swing":
		# cung quét ngang trước người
		for i in range(17):
			x = 7.5 + i
			y = 22 + bob - 1.4 * math.sin(math.pi * i / 16)
			c.put(x, y, "wood" if 0 < i < 16 else "gold", 0 if i < 8 else 1)
	elif stage == "low":
		for i in range(13):
			x = 4 + i * 0.7
			y = 18 + bob + i * 0.75 - 0.05 * (i - 6) ** 2
			c.put(x, y, "wood" if 0 < i < 12 else "gold", 1)
	smear = p.get("smear")
	if smear:
		c.zc += 1
		a0, a1 = smear
		for r, lv in ((13.0, 0), (12.0, 1), (11.0, 2)):
			for k in range(48):
				a = a0 + (a1 - a0) * k / 47
				x = 15.5 + math.cos(a) * r
				y = 20 + bob + math.sin(a) * r * 0.55
				ix, iy = int(math.floor(x)), int(math.floor(y))
				if c.inside(ix, iy) and c.mat[iy][ix] is None:
					c.put(x, y, "smear", lv, ao=False)
	return c


# ------------------------------------------------------------------ Danh sách animation

def anims() -> dict[str, tuple[list[Canvas], float, bool]]:
	"""name -> (frames, fps, loop)"""
	out: dict[str, tuple[list[Canvas], float, bool]] = {}
	# idle: thở nhẹ + tóc đung đưa + chớp mắt
	idle = [dict(bob=0, sway=0), dict(bob=0, sway=1, scarf=1), dict(bob=1, sway=1, scarf=1), dict(bob=1, sway=0, blink=True)]
	out["idle_down"] = ([draw_front(p) for p in idle], 4.0, True)
	out["idle_up"] = ([draw_back(p) for p in idle], 4.0, True)
	out["idle_side"] = ([draw_side(dict(p, sway=p["sway"] + 1)) for p in idle], 4.0, True)

	walk_fb = [
		dict(bob=0, lift_l=1, sway=1, scarf=1, arm_l=1, arm_r=-1),
		dict(bob=-1, sway=2, scarf=2),
		dict(bob=0, lift_r=1, sway=1, scarf=1, arm_l=-1, arm_r=1),
		dict(bob=-1, sway=2, scarf=2),
	]
	out["walk_down"] = ([draw_front(p) for p in walk_fb], 8.0, True)
	out["walk_up"] = ([draw_back(p) for p in walk_fb], 8.0, True)
	near = [3, 1, -1, -2, -1, 1]
	walk_side = []
	for i, n in enumerate(near):
		walk_side.append(dict(
			near=n, far=-n, bob=0 if i in (0, 3) else -1, sway=3 + (i % 2), scarf=1 + (i % 3 == 1),
			lift_near=1 if i in (4, 5) else 0, lift_far=1 if i in (1, 2) else 0,
		))
	out["walk_side"] = ([draw_side(p) for p in walk_side], 11.0, True)

	# attack: giơ cung → quét (vệt chém) → theo đà → thu về
	side_atk = [
		dict(arm="up", lean=-1, sway=2),
		dict(arm="swing", lean=1, sway=4, smear=(-1.3, 0.6), near=1, far=-1),
		dict(arm="low", lean=1, sway=4, smear=(-0.2, 1.0), near=1, far=-1),
		dict(arm="low", lean=0, sway=3),
	]
	out["attack_side"] = ([draw_side(p) for p in side_atk], 14.0, False)
	fa = [
		dict(stage="up", sway=1),
		dict(stage="swing", sway=2, smear=(-0.3, 3.4), lift_l=1),
		dict(stage="low", sway=2, smear=(1.2, 3.0)),
		dict(stage="low", sway=1),
	]
	out["attack_down"] = ([front_attack(p, False) for p in fa], 14.0, False)
	out["attack_up"] = ([front_attack(dict(p, smear=(p["smear"][0] + math.pi, p["smear"][1] + math.pi) if p.get("smear") else None), True) for p in fa], 14.0, False)

	# dodge: lướt nhanh, tóc + khăn bay mạnh
	out["dodge_side"] = ([draw_side(dict(lean=2, bob=1, sway=6, scarf=3, near=3, far=-3, lift_far=1)),
			draw_side(dict(lean=2, bob=1, sway=7, scarf=4, near=3, far=-3, lift_far=1, blink=True)),
			draw_side(dict(lean=1, bob=0, sway=5, scarf=2, near=1, far=-1))], 12.0, False)
	out["dodge_down"] = ([draw_front(dict(bob=1, sway=3, scarf=3, lift_l=1)), draw_front(dict(bob=1, sway=-3, scarf=3, lift_r=1, blink=True)),
			draw_front(dict(bob=0, sway=1, scarf=1))], 12.0, False)
	out["dodge_up"] = ([draw_back(dict(bob=1, sway=3, scarf=3, lift_l=1)), draw_back(dict(bob=1, sway=-3, scarf=3, lift_r=1)),
			draw_back(dict(bob=0, sway=1, scarf=1))], 12.0, False)

	# hurt: giật lùi, nhắm mắt
	out["hurt_down"] = ([draw_front(dict(head_dy=-1, pain=True, sway=-2, scarf=-1, arm_l=-1, arm_r=-1)), draw_front(dict(bob=1, pain=True, sway=-1))], 6.0, False)
	out["hurt_up"] = ([draw_back(dict(head_dy=-1, sway=-2, arm_l=-1, arm_r=-1)), draw_back(dict(bob=1, sway=-1))], 6.0, False)
	out["hurt_side"] = ([draw_side(dict(lean=-1, head_dy=-1, pain=True, sway=-1, near=-1, far=1)), draw_side(dict(lean=-1, bob=1, pain=True, sway=0))], 6.0, False)
	# jump: khung 0 bật lên (co hai chân, tóc rủ thẳng), khung 1 rơi (tay giơ, khăn + tóc bay)
	jump_up = dict(bob=-1, sway=0, scarf=0, lift_l=2, lift_r=2, arm_l=1, arm_r=1)
	jump_fall = dict(bob=0, head_dy=1, sway=-2, scarf=3, lift_l=1, arm_l=-2, arm_r=-2)
	out["jump_down"] = ([draw_front(jump_up), draw_front(jump_fall)], 1.0, False)
	out["jump_up"] = ([draw_back(jump_up), draw_back(jump_fall)], 1.0, False)
	out["jump_side"] = ([draw_side(dict(bob=-1, lean=1, sway=1, near=2, far=-1, lift_near=2, lift_far=2)),
			draw_side(dict(bob=0, head_dy=1, sway=-2, scarf=3, near=1, far=-2, lift_far=1))], 1.0, False)
	return out


ORDER = ["idle", "walk", "attack", "dodge", "hurt", "jump"]
DIRS = ["down", "up", "side"]


def build() -> tuple[Image.Image, list[tuple[str, int, int, float, bool]]]:
	data = anims()
	names = [f"{a}_{d}" for a in ORDER for d in DIRS]
	cols = max(len(data[n][0]) for n in names)
	sheet = Image.new("RGBA", (cols * W, len(names) * H), (0, 0, 0, 0))
	meta = []
	for row, name in enumerate(names):
		frames, fps, loop = data[name]
		for i, cv in enumerate(frames):
			sheet.paste(cv.render(), (i * W, row * H))
		meta.append((name, row, len(frames), fps, loop))
	return sheet, meta


def write_frames(meta: list[tuple[str, int, int, float, bool]]) -> None:
	lines = []
	subs = []
	anim_blocks = []
	sid = 0
	for name, row, count, fps, loop in meta:
		frames = []
		for i in range(count):
			sid += 1
			subs.append(
				f'[sub_resource type="AtlasTexture" id="Atlas_{sid}"]\natlas = ExtResource("1_sheet")\n'
				f"region = Rect2({i * W}, {row * H}, {W}, {H})\n"
			)
			# khung cuối của attack giữ lâu hơn
			dur = 2.0 if name.startswith("attack") and i == count - 1 else 1.0
			frames.append(f'{{\n"duration": {dur},\n"texture": SubResource("Atlas_{sid}")\n}}')
		anim_blocks.append(
			'{\n"frames": [' + ", ".join(frames) + f'],\n"loop": {"true" if loop else "false"},\n'
			f'"name": &"{name}",\n"speed": {fps}\n}}'
		)
	lines.append(f'[gd_resource type="SpriteFrames" load_steps={sid + 2} format=3]\n')
	lines.append(f'[ext_resource type="Texture2D" path="{SHEET_RES}" id="1_sheet"]\n')
	lines.extend(subs)
	lines.append("[resource]\nanimations = [" + ", ".join(anim_blocks) + "]\n")
	FRAMES_PATH.write_text("\n".join(lines), encoding="utf-8")


def preview(sheet: Image.Image, meta, path: str) -> None:
	scale = 6
	bg = Image.new("RGBA", sheet.size, (104, 150, 72, 255))
	bg.alpha_composite(sheet)
	big = bg.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)
	big.save(path)


def main() -> None:
	sheet, meta = build()
	if "--preview" in sys.argv:
		preview(sheet, meta, sys.argv[sys.argv.index("--preview") + 1])
		if "--no-write" in sys.argv:
			return
	SHEET_PATH.parent.mkdir(parents=True, exist_ok=True)
	sheet.save(SHEET_PATH)
	write_frames(meta)
	print(f"sheet {sheet.size} -> {SHEET_PATH}")
	print(f"frames -> {FRAMES_PATH}")


if __name__ == "__main__":
	main()
