"""Kiểm tra nhanh dự án Godot — bằng chứng cho bước verify của /game-cook và /game-review.

Các bước (dừng ở bước đầu tiên có lỗi nếu không có --keep-going):
  0. warm manifest : (thuần Python, không cần Godot) mọi preload("res://…") trong src/**/*.gd và
                     #include "res://…" trong shader phải khớp _WARM_PRELOADS/_WARM_INCLUDES của
                     src/autoload/scene_manager.gd (né rò ObjectDB godot#120661). Giới hạn: chỉ quét
                     preload/include viết trên 1 dòng; không thấy preload lồng trong preload target.
  1. import      : godot --headless --import (bắt lỗi resource/import)
  2. parse         : godot --check-only --script cho từng file .gd (mặc định: file .gd đã đổi so với HEAD + file mới)
  3. run           : chạy game headless N frame, gom SCRIPT ERROR / ERROR / WARNING
  3b. run stress   : (chỉ --all) nạp headless bench_stress.tscn 600 frame — `--import` không kiểm .tscn,
                     lỗi bản sao stress chỉ lộ khi nạp thật (in ERROR nhưng rc=0 → kiểm thêm dòng [WaterField])
  4. shots (tùy)   : chụp màn hình day / sunset / night vào thư mục --shots

Warning/lỗi đã biết, chấp nhận tạm thời, ghi trong tools/dev/known_issues.txt (mỗi dòng một regex).

Ví dụ:
  python tools/dev/check.py                       # file .gd đã đổi + chạy 120 frame
  python tools/dev/check.py --all                 # parse toàn bộ src/**/*.gd
  python tools/dev/check.py --shots plans/<plan>/artifacts/shots
  python tools/dev/check.py --shots out --lighting night --pos=-9,3

Exit 0 = sạch, 1 = có lỗi, 2 = không chạy được Godot.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_GODOT = "C:/ProgramData/chocolatey/lib/godot/tools/Godot_v4.7.2-stable_win64_console.exe"
KNOWN_FILE = ROOT / "tools" / "dev" / "known_issues.txt"
STRESS_LEVEL = "res://src/world/levels/bench_stress/bench_stress.tscn"
ANSI = re.compile(r"\x1b\[[0-9;]*m")
PROBLEM = re.compile(r"^(SCRIPT ERROR|ERROR|WARNING|USER ERROR|USER WARNING):")


def godot_exe() -> str:
    exe = os.environ.get("GODOT", DEFAULT_GODOT)
    if not Path(exe).is_file():
        print(f"[check] không tìm thấy Godot: {exe} (đặt biến môi trường GODOT)", file=sys.stderr)
        sys.exit(2)
    return exe


def load_known() -> list[re.Pattern[str]]:
    if not KNOWN_FILE.is_file():
        return []
    pats: list[re.Pattern[str]] = []
    for line in KNOWN_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            pats.append(re.compile(line))
    return pats


def run(cmd: list[str], timeout: int) -> tuple[int, list[str]]:
    try:
        p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, [f"TIMEOUT sau {timeout}s: {' '.join(cmd)}"]
    lines = [ANSI.sub("", ln) for ln in (p.stdout + "\n" + p.stderr).splitlines()]
    return p.returncode, lines


def problems(lines: list[str], known: list[re.Pattern[str]]) -> tuple[list[str], int]:
    """Trả về (các khối lỗi mới, số dòng bị lọc vì đã biết). Gộp dòng `at:` ngay sau vào cùng khối."""
    out: list[str] = []
    ignored = 0
    i = 0
    while i < len(lines):
        ln = lines[i]
        if PROBLEM.match(ln):
            block = ln
            if i + 1 < len(lines) and lines[i + 1].strip().startswith("at:"):
                block += "\n    " + lines[i + 1].strip()
                i += 1
            if any(k.search(block) for k in known):
                ignored += 1
            else:
                out.append(block)
        i += 1
    return out, ignored


def autoload_noise() -> list[re.Pattern[str]]:
    """`--check-only --script` không nạp autoload → mọi tham chiếu EventBus/GameState... báo lỗi giả.
    Lọc lỗi đó + các dòng dây chuyền của nó. Hạn chế: compile dừng ở lỗi đầu, nên lỗi compile thật nằm
    SAU dòng dùng autoload có thể bị che — bước `run` headless (nạp autoload thật) bắt phần đó."""
    text = (ROOT / "project.godot").read_text(encoding="utf-8")
    sec = re.search(r"^\[autoload\]\s*$(.*?)(?=^\[|\Z)", text, re.M | re.S)
    names = re.findall(r"^(\w+)\s*=", sec.group(1), re.M) if sec else []
    pats = [re.compile(r"Failed to compile depended scripts"),
            re.compile(r'Failed to load script ".*" with error "Compilation failed"')]
    if names:
        pats.insert(0, re.compile(r"Identifier not found: (%s)\b" % "|".join(names)))
    return pats


def changed_gd_files() -> list[str]:
    files: set[str] = set()
    for args in (["git", "diff", "--name-only", "HEAD"],
                 ["git", "ls-files", "--others", "--exclude-standard"]):
        p = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
        files.update(f for f in p.stdout.splitlines() if f.endswith(".gd"))
    return sorted(f for f in files if (ROOT / f).is_file())


SCENE_MANAGER = ROOT / "src" / "autoload" / "scene_manager.gd"
PRELOAD_RE = re.compile(r'preload\(\s*"([^"]+)"\s*\)')
INCLUDE_RE = re.compile(r'^\s*#include\s+"([^"]+)"')


def _manifest(text: str, name: str) -> set[str]:
    m = re.search(r"const %s[^=]*=\s*\[(.*?)\]" % name, text, re.S)
    return set(re.findall(r'"(res://[^"]+)"', m.group(1))) if m else set()


def warm_manifest_problems() -> tuple[int, int, list[str]]:
    """(số file manifest, tổng byte trên đĩa, danh sách lỗi). Xem docstring đầu file, bước 0."""
    errs: list[str] = []
    used: dict[str, dict[str, list[str]]] = {"_WARM_PRELOADS": {}, "_WARM_INCLUDES": {}}
    src = ROOT / "src"
    scans = [("_WARM_PRELOADS", PRELOAD_RE, sorted(src.rglob("*.gd")))]
    scans.append(("_WARM_INCLUDES", INCLUDE_RE,
                  sorted([*src.rglob("*.gdshader"), *src.rglob("*.gdshaderinc")])))
    for kind, pat, files in scans:
        for f in files:
            rel = f.relative_to(ROOT).as_posix()
            for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
                if kind == "_WARM_PRELOADS" and line.strip().startswith("#"):
                    continue
                for path in pat.findall(line):
                    if not path.startswith("res://"):
                        errs.append(f"{rel}:{n} → {path} (không phải res://)")
                    else:
                        used[kind].setdefault(path, []).append(f"{rel}:{n}")
    text = SCENE_MANAGER.read_text(encoding="utf-8")
    total_files = 0
    total_bytes = 0
    for kind, refs in used.items():
        listed = _manifest(text, kind)
        for path in sorted(set(refs) - listed):
            errs.append(f"{', '.join(refs[path])} → {path} (thiếu trong {kind})")
        for path in sorted(listed - set(refs)):
            errs.append(f"{kind} → {path} (thừa: không còn ai dùng)")
        for path in listed:
            disk = ROOT / path[len("res://"):]
            if disk.is_file():
                total_files += 1
                total_bytes += disk.stat().st_size
            else:
                errs.append(f"{kind} → {path} (file không tồn tại)")
    return total_files, total_bytes, errs


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--all", action="store_true", help="parse mọi src/**/*.gd thay vì chỉ file đã đổi")
    ap.add_argument("--files", nargs="*", help="danh sách .gd cụ thể (đường dẫn tương đối repo)")
    ap.add_argument("--frames", type=int, default=120, help="số frame chạy headless (0 = bỏ bước run)")
    ap.add_argument("--shots", help="thư mục lưu screenshot day/sunset/night (bỏ trống = không chụp)")
    ap.add_argument("--lighting", nargs="*", default=["day", "sunset", "night"])
    ap.add_argument("--delay", type=float, default=3.0)
    ap.add_argument("--extra", nargs="*", default=[], help="tham số dev thêm cho game, vd --extra=--pos=-9,3")
    ap.add_argument("--keep-going", action="store_true", help="không dừng khi một bước lỗi")
    a = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # console Windows mặc định cp1252

    failed = False
    # 0. warm manifest — trước godot_exe() để chạy được cả khi không có Godot
    n_files, n_bytes, errs = warm_manifest_problems()
    print(f"[{'FAIL' if errs else 'PASS'}] warm manifest ({n_files} file, {n_bytes / 1024:.1f} KB)")
    for e in errs:
        print("    " + e)
    if errs:
        failed = True
        if not a.keep_going:
            return 1

    exe = godot_exe()
    known = load_known()
    total_ignored = 0

    def report(step: str, rc: int, lines: list[str]) -> bool:
        nonlocal total_ignored
        found, ignored = problems(lines, known)
        total_ignored += ignored
        ok = rc == 0 and not found
        print(f"[{'PASS' if ok else 'FAIL'}] {step} (rc={rc}, lỗi mới={len(found)}, đã biết={ignored})")
        for f in found:
            print("    " + f.replace("\n", "\n    "))
        if rc != 0 and not found:
            print("    " + "\n    ".join(lines[-8:]))
        return ok

    # 1. import
    rc, lines = run([exe, "--headless", "--path", ".", "--import"], timeout=600)
    if not report("import", rc, lines):
        failed = True
        if not a.keep_going:
            return 1

    # 2. parse
    if a.files:
        targets = a.files
    elif a.all:
        targets = sorted(str(p.relative_to(ROOT)).replace("\\", "/") for p in (ROOT / "src").rglob("*.gd"))
    else:
        targets = changed_gd_files()
    parse_ok = True
    noise = autoload_noise()
    for f in targets:
        rc, lines = run([exe, "--headless", "--path", ".", "--check-only", "--script", "res://" + f], timeout=120)
        found, ignored = problems(lines, known)
        total_ignored += ignored
        found = [b for b in found if not any(n.search(b) for n in noise)]
        if found or (rc != 0 and not any(PROBLEM.match(ln) for ln in lines)):
            parse_ok = False
            print(f"    {f}:")
            for b in found or lines[-6:]:
                print("      " + b.replace("\n", "\n      "))
    print(f"[{'PASS' if parse_ok else 'FAIL'}] parse ({len(targets)} file .gd)")
    if not parse_ok:
        failed = True
        if not a.keep_going:
            return 1

    # 3. run headless
    if a.frames > 0:
        rc, lines = run([exe, "--headless", "--path", ".", "--quit-after", str(a.frames), "--", *a.extra],
                        timeout=300)
        if not report(f"run headless {a.frames} frame", rc, lines):
            failed = True
            if not a.keep_going:
                return 1

    # 3b. nạp level stress (chỉ --all)
    if a.all and a.frames > 0:
        if not (ROOT / STRESS_LEVEL[len("res://"):]).is_file():
            print("[SKIP] run stress (không có bench_stress.tscn)")
        else:
            rc, lines = run([exe, "--headless", "--path", ".", "--quit-after", "600", "--",
                             f"--level={STRESS_LEVEL}"], timeout=300)
            ok = report("run stress 600 frame", rc, lines)
            if not any(ln.startswith("[WaterField]") for ln in lines):
                print("    thiếu dòng [WaterField] → level stress không nạp tới _ready:")
                print("    " + "\n    ".join(lines[-8:]))
                ok = False
            if not ok:
                failed = True
                if not a.keep_going:
                    return 1

    # 4. screenshots (cần GPU, không headless)
    if a.shots:
        out_dir = Path(a.shots)
        if not out_dir.is_absolute():
            out_dir = ROOT / out_dir
        out_dir.mkdir(parents=True, exist_ok=True)
        for mood in a.lighting:
            png = (out_dir / f"{mood}.png").as_posix()
            rc, lines = run([exe, "--path", ".", "--", f"--screenshot={png}", f"--delay={a.delay}",
                             f"--lighting={mood}", *a.extra], timeout=180)
            ok = report(f"screenshot {mood}", rc, lines) and Path(png).is_file()
            print(f"    -> {png}" if ok else "    -> không có ảnh")
            failed = failed or not ok

    print(f"\nKẾT QUẢ: {'FAIL' if failed else 'PASS'}" + (f" (bỏ qua {total_ignored} dòng đã biết)" if total_ignored else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
