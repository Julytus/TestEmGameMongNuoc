"""Quản lý plan cho luồng /game-plan → /game-cook → /game-review.

  python tools/dev/plan.py new --slug lake-foam --title "Bọt nước sát bờ" --phases shader,material,tune [--mode hard|fast]
  python tools/dev/plan.py approve plans/<dir> --by "<tên người duyệt>" [--note "..."]
  python tools/dev/plan.py status  plans/<dir>        # duyệt còn hiệu lực? phase nào đã có verification?
  python tools/dev/plan.py list

Duyệt gắn với NỘI DUNG: hash plan.md (bỏ frontmatter) + mọi phases/*.md + refs/*. Sửa plan sau khi duyệt
→ status báo DRIFT và /game-cook phải dừng để người dùng duyệt lại.
Exit: status → 0 khi đã duyệt & còn hiệu lực, 1 khi chưa duyệt / drift.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLANS = ROOT / "plans"
TPL = ROOT / ".claude" / "skills" / "game-plan" / "templates"
FRONT = re.compile(r"\A---\n.*?\n---\n", re.S)


def ensure_plans_dir() -> None:
    PLANS.mkdir(exist_ok=True)
    (PLANS / ".gdignore").touch()  # Godot không import thư mục plans/
    (PLANS / "reports").mkdir(exist_ok=True)


def plan_files(d: Path) -> list[Path]:
    files = [d / "plan.md"] + sorted((d / "phases").glob("phase-*.md"))
    if (d / "refs").is_dir():
        files += sorted(p for p in (d / "refs").rglob("*") if p.is_file())
    return [f for f in files if f.is_file()]


def content_hash(d: Path) -> tuple[str, dict[str, str]]:
    per: dict[str, str] = {}
    h = hashlib.sha256()
    for f in plan_files(d):
        text = f.read_text(encoding="utf-8").replace("\r\n", "\n")
        if f.name == "plan.md":
            text = FRONT.sub("", text, count=1)  # frontmatter (status...) không tính vào hash
        rel = f.relative_to(d).as_posix()
        per[rel] = hashlib.sha256(text.encode()).hexdigest()[:12]
        h.update(rel.encode() + b"\0" + text.encode() + b"\0")
    return h.hexdigest()[:16], per


def set_front(d: Path, key: str, value: str) -> None:
    p = d / "plan.md"
    text = p.read_text(encoding="utf-8")
    m = FRONT.match(text)
    if not m:
        return
    block = m.group(0)
    if re.search(rf"^{key}:.*$", block, re.M):
        block = re.sub(rf"^{key}:.*$", f"{key}: {value}", block, count=1, flags=re.M)
    else:
        block = block[:-4] + f"{key}: {value}\n---\n"
    p.write_text(block + text[m.end():], encoding="utf-8")


def cmd_new(a: argparse.Namespace) -> int:
    ensure_plans_dir()
    now = dt.datetime.now()
    slug = re.sub(r"[^a-z0-9-]+", "-", a.slug.lower()).strip("-")
    d = PLANS / f"{now:%y%m%d-%H%M}-{slug}"
    if d.exists():
        print(f"đã tồn tại: {d}", file=sys.stderr)
        return 1
    phases = [p.strip() for p in a.phases.split(",") if p.strip()]
    (d / "phases").mkdir(parents=True)
    (d / "artifacts").mkdir()
    (d / "reports").mkdir()
    rows = []
    phase_list = []
    tpl_phase = (TPL / "phase.md").read_text(encoding="utf-8")
    for i, name in enumerate(phases, 1):
        fn = f"phase-{i}-{re.sub(r'[^a-z0-9-]+', '-', name.lower()).strip('-')}.md"
        (d / "phases" / fn).write_text(
            tpl_phase.replace("{{ID}}", f"P{i}").replace("{{NAME}}", name), encoding="utf-8")
        rows.append(f"| P{i} | [{name}](phases/{fn}) | — |")
        phase_list.append(f"  - phases/{fn}")
    plan = (TPL / "plan.md").read_text(encoding="utf-8")
    plan = (plan.replace("{{TITLE}}", a.title).replace("{{MODE}}", a.mode)
                .replace("{{DATE}}", f"{now:%Y-%m-%d}").replace("{{PHASE_LIST}}", "\n".join(phase_list))
                .replace("{{PHASE_ROWS}}", "\n".join(rows)))
    (d / "plan.md").write_text(plan, encoding="utf-8")
    print(d.as_posix())
    return 0


def cmd_approve(a: argparse.Namespace) -> int:
    d = Path(a.plan).resolve()
    if not (d / "plan.md").is_file():
        print(f"không thấy plan.md trong {d}", file=sys.stderr)
        return 1
    digest, per = content_hash(d)
    rec = {"verdict": "APPROVED", "by": a.by, "note": a.note,
           "at": dt.datetime.now().isoformat(timespec="seconds"), "hash": digest, "files": per}
    (d / "artifacts").mkdir(exist_ok=True)
    (d / "artifacts" / "approval.json").write_text(json.dumps(rec, ensure_ascii=False, indent=2), encoding="utf-8")
    set_front(d, "status", "approved")
    print(f"APPROVED {digest} by {a.by}")
    return 0


def cmd_status(a: argparse.Namespace) -> int:
    d = Path(a.plan).resolve()
    appr = d / "artifacts" / "approval.json"
    digest, per = content_hash(d)
    ok = False
    if not appr.is_file():
        print("approval: CHƯA DUYỆT")
    else:
        rec = json.loads(appr.read_text(encoding="utf-8"))
        if rec.get("hash") == digest:
            ok = True
            print(f"approval: OK ({rec['hash']}, {rec.get('by')}, {rec.get('at')})")
        else:
            old: dict[str, str] = rec.get("files", {})
            moved = sorted({k for k in per if old.get(k) != per[k]} | {k for k in old if k not in per})
            print(f"approval: DRIFT — plan đã sửa sau khi duyệt: {', '.join(moved)}")
    for f in sorted((d / "phases").glob("phase-*.md")):
        pid = "P" + f.name.split("-")[1]
        ver = d / "artifacts" / f"verification-{pid}.md"
        verdict = "chưa làm"
        if ver.is_file():
            m = re.search(r"^verdict:\s*(\S+)", ver.read_text(encoding="utf-8"), re.M)
            verdict = m.group(1) if m else "có file, thiếu dòng verdict"
        print(f"  {pid} {f.name}: {verdict}")
    rv = d / "artifacts" / "review.md"
    if rv.is_file():
        m = re.search(r"^verdict:\s*(\S+)", rv.read_text(encoding="utf-8"), re.M)
        print(f"review: {m.group(1) if m else 'thiếu dòng verdict'}")
    else:
        print("review: chưa có")
    return 0 if ok else 1


def cmd_list(_: argparse.Namespace) -> int:
    if not PLANS.is_dir():
        return 0
    for d in sorted(p for p in PLANS.iterdir() if (p / "plan.md").is_file()):
        m = re.search(r"^status:\s*(\S+)", (d / "plan.md").read_text(encoding="utf-8"), re.M)
        print(f"{d.name}  [{m.group(1) if m else '?'}]")
    return 0


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    n = sub.add_parser("new")
    n.add_argument("--slug", required=True)
    n.add_argument("--title", required=True)
    n.add_argument("--phases", required=True, help="tên phase, cách nhau bởi dấu phẩy")
    n.add_argument("--mode", choices=["hard", "fast"], default="hard")
    p = sub.add_parser("approve")
    p.add_argument("plan")
    p.add_argument("--by", required=True)
    p.add_argument("--note", default="")
    s = sub.add_parser("status")
    s.add_argument("plan")
    sub.add_parser("list")
    a = ap.parse_args()
    return {"new": cmd_new, "approve": cmd_approve, "status": cmd_status, "list": cmd_list}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
