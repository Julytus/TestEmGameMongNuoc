"""Bench hiệu năng tự động — chạy ma trận cấu hình bằng `godot -- --bench=N`, so với docs/perf_baseline.json, in bảng.

Mỗi cấu hình = 1 tiến trình Godot (exclusive fullscreen 1920x1080, chạy NỐI TIẾP — không bao giờ hai Godot cùng lúc),
đo N giây ở mỗi BenchPoint của level, ghi JSON (schema 1, xem src/dev/bench/bench_runner.gd).

Ma trận:
  mặc định : meadow_road × {low, medium, high} × {gpu0, gpu1} × day                  (6 cấu hình)
  --stress : + bench_stress × 3 mức × 2 GPU × day                                    (+6)
  --full   : mặc định + meadow sunset/night + stress (chỉ day)                        (24)
  --gpus 0,1 / --qualities low,high : lọc (thử nhanh)

Luật (nguồn ngưỡng duy nhất — hằng bên dưới):
  [ĐỎ]   GPU p50: now > base × (1 + REGRESS_PCT) VÀ now − base > REGRESS_ABS_MS. CPU chỉ in.
  nhiễu  điểm có gpu p95 > R × p50 (R: dGPU 1,05 · iGPU 1,10) → chạy bù cấu hình 1 lần, giữ lần ít nhiễu hơn.
  smoke  seconds_per_point khác baseline (vd --seconds 2) → không so.
  khác-môi-trường  Godot/driver khác baseline của khóa → không tính đỏ, đề nghị chụp lại baseline.
  [ĐỎ] so baseline giữa các phiên chỉ là TÍN HIỆU; kết luận "X làm chậm" phải dựa A/B cùng phiên.

Ví dụ:
  python tools/bench/run_bench.py                         # ma trận mặc định, so baseline
  python tools/bench/run_bench.py --full --update-baseline  # chụp lại baseline (cắm điện!)
  python tools/bench/run_bench.py --gpus 0 --qualities low --seconds 3   # thử nhanh (smoke)
  python tools/bench/run_bench.py --results <dir>         # chỉ so lại JSON đã có, không chạy Godot
  python tools/bench/run_bench.py --exe build/game.exe    # bản export (khóa @export, không so baseline debug)

Exit 0 sạch (kể cả mới/smoke/khác-môi-trường) · 1 có [ĐỎ] · 2 lỗi chạy / JSON không hợp lệ / thiếu level / Godot đang chạy.
"""
from __future__ import annotations

import argparse
import ctypes
import datetime as dt
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True  # import check.py không để lại __pycache__
sys.path.insert(0, str(ROOT / "tools" / "dev"))
from check import godot_exe  # noqa: E402

REGRESS_PCT = 0.05
REGRESS_ABS_MS = 0.3
NOISE_RATIO = {"dgpu": 1.05, "igpu": 1.10}
MAX_DRIFT_M = 0.05
FRAMES_MIN_RATIO = 0.8
TIMEOUT_S = 300
ADAPTER_TYPE_INTEGRATED = 1  # RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
DEFAULT_BASELINE = ROOT / "docs" / "perf_baseline.json"
LEVELS = {
    "meadow_road": "res://src/world/levels/meadow_road/meadow_road.tscn",
    "bench_stress": "res://src/world/levels/bench_stress/bench_stress.tscn",
}
QUALITIES = ["low", "medium", "high"]
META_FIELDS = ["schema", "godot", "driver", "api_version", "adapter", "adapter_type", "resolution", "quality",
               "lighting", "level", "load_ms", "seconds_per_point"]
POINT_FIELDS = ["id", "quality", "lighting", "frames", "gpu_ms", "cpu_ms", "wall_ms", "draw_calls", "primitives",
                "vram_mb", "drift_m", "focus_lost", "sample_overflow"]
STAT_FIELDS = ["avg", "p50", "p95", "p99", "max"]
RED = "\x1b[31m" if sys.stdout.isatty() else ""
RESET = "\x1b[0m" if RED else ""


# --- cấu hình -------------------------------------------------------------------------------------------------

class Config:
    def __init__(self, level: str, quality: str, lighting: str, gpu: int, export: bool) -> None:
        self.level, self.quality, self.lighting, self.gpu, self.export = level, quality, lighting, gpu, export

    @property
    def key(self) -> str:
        return f"{self.level}/{self.quality}/{self.lighting}/gpu{self.gpu}" + ("@export" if self.export else "")

    @property
    def stem(self) -> str:
        return self.key.replace("/", "__")

    @staticmethod
    def from_stem(stem: str) -> "Config":
        key = stem.replace("__", "/")
        export = key.endswith("@export")
        level, quality, lighting, gpu = key.removesuffix("@export").split("/")
        return Config(level, quality, lighting, int(gpu.removeprefix("gpu")), export)


def build_matrix(a: argparse.Namespace) -> list[Config]:
    gpus = [int(g) for g in a.gpus.split(",")]
    quals = a.qualities.split(",")
    combos: list[tuple[str, str]] = [("meadow_road", "day")]
    if a.full:
        combos += [("meadow_road", "sunset"), ("meadow_road", "night")]
    if a.full or a.stress:
        combos.append(("bench_stress", "day"))
    return [Config(lv, q, l, g, bool(a.exe)) for lv, l in combos for q in quals for g in gpus]


# --- môi trường ------------------------------------------------------------------------------------------------

def godot_running() -> list[str]:
    try:
        out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq Godot*", "/NH"], capture_output=True, text=True,
                             errors="replace").stdout
    except OSError:
        return []
    return [ln.split()[0] for ln in out.splitlines() if ln.lower().startswith("godot")]


def on_ac_power() -> bool | None:
    """True cắm điện · False chạy pin · None không biết (không phải Windows)."""
    if os.name != "nt":
        return None

    class PowerStatus(ctypes.Structure):
        _fields_ = [("ACLineStatus", ctypes.c_ubyte), ("BatteryFlag", ctypes.c_ubyte),
                    ("BatteryLifePercent", ctypes.c_ubyte), ("SystemStatusFlag", ctypes.c_ubyte),
                    ("BatteryLifeTime", ctypes.c_ulong), ("BatteryFullLifeTime", ctypes.c_ulong)]

    st = PowerStatus()
    if not ctypes.windll.kernel32.GetSystemPowerStatus(ctypes.byref(st)):
        return None
    return st.ACLineStatus == 1


# --- chạy -----------------------------------------------------------------------------------------------------

def run_once(cfg: Config, exe: str, seconds: float, out: Path, attempt: int) -> tuple[Path, Path, int]:
    js = out / f"{cfg.stem}.try{attempt}.json"
    log = out / f"{cfg.stem}.try{attempt}.log"
    cmd = [exe, "--gpu-index", str(cfg.gpu)]
    if not cfg.export:
        cmd += ["--path", str(ROOT)]
    cmd += ["--", f"--bench={seconds:g}", f"--bench-out={js.as_posix()}", f"--quality={cfg.quality}",
            f"--lighting={cfg.lighting}", f"--level={LEVELS[cfg.level]}"]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=TIMEOUT_S)
        rc, text = p.returncode, p.stdout + "\n" + p.stderr
    except subprocess.TimeoutExpired:
        rc, text = 124, f"TIMEOUT sau {TIMEOUT_S}s"
    log.write_text(" ".join(cmd) + "\n" + text, encoding="utf-8")
    return js, log, rc


def run_config(cfg: Config, exe: str, seconds: float, out: Path, base: dict) -> tuple[Path | None, list[str]]:
    """Chạy (bù 1 lần nếu nhiễu/không hợp lệ). Trả về (JSON được chọn — đã chép thành <stem>.json, lỗi nếu không lần nào hợp lệ)."""
    tries: list[tuple[Path, Path, list[str], int]] = []
    for attempt in (1, 2):
        js, log, rc = run_once(cfg, exe, seconds, out, attempt)
        errs = validate_file(js, log, rc, cfg, base)
        noisy = len(noisy_points(load_json(js))) if not errs else 0
        tries.append((js, log, errs, noisy))
        tag = "lỗi: " + "; ".join(errs) if errs else (f"{noisy} điểm nhiễu" if noisy else "ok")
        print(f"  [{cfg.key}] lần {attempt}: {tag}", flush=True)
        if not errs and noisy == 0:
            break
    valid = [t for t in tries if not t[2]]
    if not valid:
        return None, tries[-1][2]
    best = min(reversed(valid), key=lambda t: t[3])  # hòa → lần sau
    shutil.copyfile(best[0], out / f"{cfg.stem}.json")
    shutil.copyfile(best[1], out / f"{cfg.stem}.log")
    return out / f"{cfg.stem}.json", []


# --- kiểm hợp lệ ----------------------------------------------------------------------------------------------

def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def adapter_ref(base: dict, gpu: int) -> str | None:
    for k, c in base.get("configs", {}).items():
        if k.endswith(f"/gpu{gpu}"):
            return c.get("adapter")
    return None


def validate_file(js: Path, log: Path | None, rc: int, cfg: Config, base: dict) -> list[str]:
    errs: list[str] = []
    if rc != 0:
        errs.append(f"rc={rc}")
    if log is not None and log.is_file():
        bad = [ln for ln in log.read_text(encoding="utf-8", errors="replace").splitlines()
               if ln.startswith(("SCRIPT ERROR:", "ERROR:"))]
        if bad:
            errs.append("log có lỗi: " + bad[0][:160])
    d = load_json(js)
    if not d:
        return errs + [f"không đọc được JSON {js.name}"]
    return errs + validate_data(d, cfg, base)


def validate_data(d: dict, cfg: Config, base: dict) -> list[str]:
    errs: list[str] = []
    meta = d.get("meta", {})
    pts = d.get("points", [])
    missing = [f"meta.{f}" for f in META_FIELDS if f not in meta]
    for i, p in enumerate(pts):
        missing += [f"points[{i}].{f}" for f in POINT_FIELDS if f not in p]
        for s in ("gpu_ms", "cpu_ms"):
            if s in p:
                missing += [f"points[{i}].{s}.{f}" for f in STAT_FIELDS if f not in p[s]]
        if "wall_ms" in p and "p50" not in p["wall_ms"]:
            missing.append(f"points[{i}].wall_ms.p50")
    if not pts:
        missing.append("points (rỗng)")
    if missing:
        return [f"thiếu trường: {', '.join(missing[:8])}"]
    if meta["quality"] != cfg.quality or any(p["quality"] != cfg.quality for p in pts):
        errs.append(f"quality ≠ {cfg.quality}")
    if meta["lighting"] != cfg.lighting or any(p["lighting"] != cfg.lighting for p in pts):
        errs.append(f"lighting ≠ {cfg.lighting}")
    bc = base.get("configs", {}).get(cfg.key)
    want_res = bc["resolution"] if bc else [1920, 1080]
    if meta["resolution"] != want_res:
        errs.append(f"resolution {meta['resolution']} ≠ {want_res}")
    ref = adapter_ref(base, cfg.gpu)
    if ref and meta["adapter"] != ref:
        errs.append(f"adapter '{meta['adapter']}' ≠ baseline gpu{cfg.gpu} '{ref}'")
    sp = float(meta["seconds_per_point"])
    for p in pts:
        why = []
        if p["focus_lost"]:
            why.append("focus_lost")
        if p["drift_m"] > MAX_DRIFT_M:
            why.append(f"drift {p['drift_m']:.3f} m")
        if p["sample_overflow"]:
            why.append("sample_overflow")
        wall = max(float(p["wall_ms"]["p50"]), 1e-3)
        need = FRAMES_MIN_RATIO * sp * min(60.0, 1000.0 / wall)
        if p["frames"] < need:
            why.append(f"frames {p['frames']} < {need:.0f}")
        if why:
            errs.append(f"{p['id']}: {', '.join(why)}")
    return errs


def noisy_points(d: dict) -> set[str]:
    if not d:
        return set()
    r = NOISE_RATIO["igpu" if d["meta"].get("adapter_type") == ADAPTER_TYPE_INTEGRATED else "dgpu"]
    return {p["id"] for p in d["points"] if p["gpu_ms"]["p95"] > r * p["gpu_ms"]["p50"]}


# --- so baseline ----------------------------------------------------------------------------------------------

def compare(results: list[tuple[Config, Path]], base: dict) -> tuple[int, list[str]]:
    """In bảng; trả về (số dòng đỏ, cảnh báo môi trường)."""
    rows: list[list[str]] = []
    reds = 0
    warns: list[str] = []
    for cfg, js in results:
        d = load_json(js)
        meta = d["meta"]
        bc = None if cfg.export else base.get("configs", {}).get(cfg.key)
        log = js.with_suffix(".log")
        leak = log.is_file() and "leaked" in log.read_text(encoding="utf-8", errors="replace")
        noisy = noisy_points(d)
        env_diff = False
        if bc and (bc.get("godot") != meta["godot"] or bc.get("driver") != meta["driver"]):
            env_diff = True
            w = f"{cfg.key}: {bc.get('godot')} {bc.get('driver')} → {meta['godot']} {meta['driver']}"
            warns.append(w)
        smoke = bool(bc) and float(bc.get("seconds_per_point", -1)) != float(meta["seconds_per_point"])
        for p in d["points"]:
            now = p["gpu_ms"]["p50"]
            bp = bc["points"].get(p["id"]) if bc else None
            base_s, delta_s = "-", ""
            if leak:
                status = "leak"
            elif bc is None or bp is None:
                status = "mới"
            elif smoke:
                status = "smoke"
            elif env_diff:
                status = "khác-môi-trường"
            else:
                b = bp["gpu_p50"]
                red = now > b * (1 + REGRESS_PCT) and now - b > REGRESS_ABS_MS
                status = f"{RED}[ĐỎ]{RESET}" if red else "OK"
                reds += red
            if bp:
                base_s = f"{bp['gpu_p50']:.3f}"
                delta_s = f" ({(now - bp['gpu_p50']) / bp['gpu_p50'] * 100:+.1f}%)"
            if p["id"] in noisy:
                status += " (nhiễu)"
            rows.append([cfg.key, p["id"], f"{base_s} → {now:.3f}{delta_s}", f"{p['gpu_ms']['p95']:.3f}",
                         f"{p['cpu_ms']['p50']:.3f}", str(p["draw_calls"]), f"{p['primitives'] / 1e6:.2f} M",
                         f"{p['vram_mb']:.0f}", status])
    head = ["cấu hình", "điểm", "GPU p50 base → now (Δ%)", "p95", "CPU p50", "draw", "prim", "VRAM", "trạng thái"]
    widths = [max(len(_plain(r[i])) for r in [head, *rows]) for i in range(len(head))]
    for r in [head, *rows]:
        print("  ".join(c + " " * (widths[i] - len(_plain(c))) for i, c in enumerate(r)).rstrip())
    return reds, warns


def _plain(s: str) -> str:
    return s.replace(RED, "").replace(RESET, "") if RED else s


def update_baseline(results: list[tuple[Config, Path]], path: Path) -> None:
    base = load_json(path) or {"schema": 1, "configs": {}}
    for cfg, js in results:
        d = load_json(js)
        m = d["meta"]
        base["configs"][cfg.key] = {
            "godot": m["godot"], "driver": m["driver"], "api_version": m["api_version"], "adapter": m["adapter"],
            "adapter_type": m["adapter_type"], "resolution": m["resolution"],
            "seconds_per_point": m["seconds_per_point"], "debug_build": m.get("debug_build"),
            "points": {p["id"]: {"gpu_p50": round(p["gpu_ms"]["p50"], 4), "gpu_p95": round(p["gpu_ms"]["p95"], 4),
                                 "cpu_p50": round(p["cpu_ms"]["p50"], 4), "draw_calls": p["draw_calls"],
                                 "primitives": p["primitives"], "vram_mb": round(p["vram_mb"], 1)}
                       for p in d["points"]},
        }
    base["schema"] = 1
    base["updated"] = dt.date.today().isoformat()
    base["configs"] = dict(sorted(base["configs"].items()))
    path.write_text(json.dumps(base, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"[bench] baseline → {path} ({len(results)} cấu hình cập nhật, tổng {len(base['configs'])})")


# --- main -----------------------------------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--full", action="store_true", help="+ meadow sunset/night + stress (day)")
    ap.add_argument("--stress", action="store_true", help="+ bench_stress (day)")
    ap.add_argument("--update-baseline", action="store_true", help="gộp kết quả vào baseline (phải cắm điện, không lỗi)")
    ap.add_argument("--exe", help="exe bản export (bỏ --path; khóa @export, không so baseline)")
    ap.add_argument("--seconds", type=float, default=10.0, help="giây đo MỖI điểm (khác baseline → smoke)")
    ap.add_argument("--gpus", default="0,1")
    ap.add_argument("--qualities", default=",".join(QUALITIES))
    ap.add_argument("--baseline", default=str(DEFAULT_BASELINE))
    ap.add_argument("--out-dir", help="thư mục JSON/log (mặc định %%TEMP%%/gametest-bench/<thời gian>)")
    ap.add_argument("--results", help="chỉ so lại JSON trong thư mục này, không chạy Godot")
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # console Windows mặc định cp1252 (cả --help)
    a = ap.parse_args()

    base_path = Path(a.baseline)
    base = load_json(base_path) if base_path.is_file() else {"schema": 1, "configs": {}}
    results: list[tuple[Config, Path]] = []
    errors: list[str] = []

    if a.results:
        out = Path(a.results)
        files = sorted(f for f in out.glob("*.json") if ".try" not in f.name)
        if not files:
            print(f"[bench] không có JSON trong {out}")
            return 2
        for f in files:
            cfg = Config.from_stem(f.stem)
            errs = validate_file(f, f.with_suffix(".log"), 0, cfg, base)
            if errs:
                errors.append(f"{cfg.key}: {'; '.join(errs)}")
            else:
                results.append((cfg, f))
    else:
        running = godot_running()
        if running:
            print(f"[bench] đang có tiến trình Godot: {', '.join(running)} — đóng hết rồi chạy lại (không đo chồng)")
            return 2
        if on_ac_power() is False:
            if a.update_baseline:
                print("[bench] đang chạy pin — cắm điện rồi đo lại (--update-baseline bị từ chối)")
                return 2
            print("[bench] CẢNH BÁO: đang chạy pin — số đo không so được với baseline")
        if a.exe and not Path(a.exe).is_file():
            print(f"[bench] không có exe: {a.exe}")
            return 2
        exe = a.exe or godot_exe()
        configs = build_matrix(a)
        for cfg in configs:
            if not (ROOT / LEVELS[cfg.level].removeprefix("res://")).is_file():
                print(f"[bench] level không tồn tại: {LEVELS[cfg.level]}")
                return 2
        out = Path(a.out_dir) if a.out_dir else (
            Path(tempfile.gettempdir()) / "gametest-bench" / dt.datetime.now().strftime("%Y%m%d-%H%M%S"))
        out.mkdir(parents=True, exist_ok=True)
        print(f"[bench] {len(configs)} cấu hình × {a.seconds:g} s/điểm → {out}", flush=True)
        for cfg in configs:
            js, errs = run_config(cfg, exe, a.seconds, out, base)
            if js is None:
                errors.append(f"{cfg.key}: {'; '.join(errs)}")
            else:
                results.append((cfg, js))

    for e in errors:
        print(f"[LỖI] {e}")
    if a.update_baseline:
        if errors or a.results:
            print("[bench] không cập nhật baseline (có lỗi hoặc đang ở chế độ --results)")
            return 2
        update_baseline(results, base_path)
        base = load_json(base_path)

    reds, warns = compare(results, base) if results else (0, [])
    if warns:
        print("CẢNH BÁO: Godot/driver khác baseline — đề nghị chụp lại baseline: "
              "run_bench.py --full --update-baseline (cắm điện)")
        for w in warns:
            print("  " + w)
    rc = 2 if errors else (1 if reds else 0)
    verdict = {0: "SẠCH", 1: f"{reds} dòng [ĐỎ]", 2: f"{len(errors)} lỗi"}[rc]
    print(f"\nKẾT QUẢ: {verdict} — JSON: {out}")
    print("Ghi chú: [ĐỎ] so baseline giữa các phiên chỉ là tín hiệu; kết luận 'X làm chậm' dựa A/B cùng phiên.")
    return rc


if __name__ == "__main__":
    sys.exit(main())
