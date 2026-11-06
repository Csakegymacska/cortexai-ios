#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/night_gym.py — éjszakai (folyamatos) edzőciklus a Cortex Phantom Core-nak.

3 óránként: konstíciós kör + gym-kör → az eredmény KUMULATÍVAN a workspace-ben
(cortex-phantom/data/training/) gyűlik, prompt szerint deduplikálva. A /var/tmp
NEM perzisztens — ide soha ne írj tanítási adatot.

  python3 tools/night_gym.py            # végig fut, amíg le nem állítják
  python3 tools/night_gym.py --once     # egyetlen kör
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path("/home/user")
TRAIN = ROOT / "cortex-phantom/data/training"
TMP = ROOT / "cortex-phantom/data/.tmp-round"


def merge(filename: str) -> int:
    """Az új kör sorait beolvasztja a gyűjtőfájlba, prompt szerint deduplikálva."""
    src = TMP / filename
    dst = TRAIN / filename
    if not src.exists():
        return 0
    seen, rows = set(), []
    if dst.exists():
        for line in dst.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            r = json.loads(line)
            k = json.dumps(r.get("prompt", r.get("messages", [{}])[0]), ensure_ascii=False)[:140]
            seen.add(k)
            rows.append(r)
    added = 0
    for line in src.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        r = json.loads(line)
        k = json.dumps(r.get("prompt", r.get("messages", [{}])[0]), ensure_ascii=False)[:140]
        if k not in seen:
            seen.add(k)
            rows.append(r)
            added += 1
    dst.write_text("\n".join(json.dumps(x, ensure_ascii=False) for x in rows) + "\n", encoding="utf-8")
    return added


def one_round(i: int) -> None:
    print(f"── kör {i} · {time.strftime('%m-%d %H:%M')} ──", flush=True)
    TMP.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, str(ROOT / "tools/phantom_constitution.py"),
                    "--mode", "synth", "--prompts", "10", "--workers", "2",
                    "--out", str(TMP)], check=False, timeout=900)
    subprocess.run([sys.executable, str(ROOT / "tools/phantom_gym.py"),
                    "--tasks", "8", "--out", str(TMP)], check=False, timeout=900)
    added = {f: merge(f) for f in ("sl-cai.jsonl", "prefs.jsonl", "gym-sft.jsonl", "gym-prefs.jsonl")}
    total = {}
    for f in ("sl-cai.jsonl", "prefs.jsonl", "gym-sft.jsonl", "gym-prefs.jsonl"):
        p = TRAIN / f
        total[f] = sum(1 for _ in p.open()) if p.exists() else 0
    (TRAIN / "manifest.json").write_text(json.dumps(
        {"updated": time.strftime("%Y-%m-%dT%H:%M:%S"), "added_last_round": added,
         "totals": total}, indent=1, encoding="utf-8"))
    print(f"   új: {added} · összesen: {total}", flush=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--once", action="store_true")
    ap.add_argument("--every-hours", type=float, default=3.0)
    a = ap.parse_args()
    i = 0
    while True:
        i += 1
        try:
            one_round(i)
        except Exception as e:  # noqa: BLE001
            print(f"kör hiba: {e}", flush=True)
        if a.once:
            break
        time.sleep(a.every_hours * 3600)


if __name__ == "__main__":
    main()
