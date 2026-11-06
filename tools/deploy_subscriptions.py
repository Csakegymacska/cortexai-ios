#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/deploy_subscriptions.py — CORTEX SUBS (Revolut-előfizetés + AI-profil) deploy.

Letölti az ÉLŐ cortexanime workert, lecseréli benne az API-platform modult a
friss `tools/cortex_api_module.js`-re (kvóta-javítás + Revolut-kódok + egyedi
AI-profil + tulajdonosi grant), hozzáadja az új route-okat, és feltölti a
bevált mintával (backup + keep_bindings).

  python3 tools/deploy_subscriptions.py --check   # csak állapot
  python3 tools/deploy_subscriptions.py           # patch + deploy
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path

import requests

ROOT = Path("/home/user")
MODULE = ROOT / "tools/cortex_api_module.js"
BACKUP = ROOT / "cloudflare/cortexanime/backups"

env: dict[str, str] = {}
for line in (ROOT / "secrets/.env").read_text().splitlines():
    line = line.strip()
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")

ACC = env["CF_ACCOUNT_ID"]
API = f"https://api.cloudflare.com/client/v4/accounts/{ACC}/workers/scripts/cortexanime"
H = {"X-Auth-Email": env["CLOUDFLARE_EMAIL"], "X-Auth-Key": env["CLOUDFLARE_API_KEY"]}

MODULE_START = "/* ============================================================================\n   CORTEX API PLATFORM"
ANCHOR = "async function getSessionUser(req, env) {"
NEW_ROUTE = (
    '  if (requestUrl.pathname.startsWith("/api/sub/") || requestUrl.pathname === "/api/me/ai" '
    '|| requestUrl.pathname === "/api/me/ai/") return capSubApi(request2, requestUrl, env);\n'
)


def live_script() -> str:
    r = requests.get(API, headers=H, timeout=180)
    r.raise_for_status()
    ctype = r.headers.get("content-type", "")
    if not ctype.startswith("multipart/form-data"):
        return r.content.decode("utf-8", "replace")
    boundary = ctype.split("boundary=")[1].strip('"').encode()
    for part in r.content.split(b"--" + boundary):
        head, _, payload = part.partition(b"\r\n\r\n")
        if b'name="worker.js"' in head or b"filename=" in head:
            return payload.rstrip(b"\r\n").decode("utf-8", "replace")
    raise SystemExit("nincs modul a multipart válaszban")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()

    src = live_script()
    print("élő worker:", len(src), "karakter")
    if a.check:
        print("  CAP_TIERS régi (50M):", "50_000_000" in src)
        print("  capSubApi:", "capSubApi" in src)
        print("  cortex_sub_codes:", "cortex_sub_codes" in src)
        return

    module = MODULE.read_text(encoding="utf-8")

    # 1) modul-csere: a régi modul régiója a header-től az anchorig
    ai = src.index(ANCHOR)
    mi = src.rindex(MODULE_START, 0, ai)
    src = src[:mi] + module + "\n" + src[ai:]
    print("modul lecserélve ✓")

    # 2) új route (ha még nincs)
    if "/api/sub/" not in src:
        anchor2 = "  /* CORTEXAPI_V1 — API-platform */"
        if anchor2 in src:
            src = src.replace(anchor2, anchor2 + "\n" + NEW_ROUTE.rstrip("\n"), 1)
        else:
            raise SystemExit("nincs CORTEXAPI_V1 route-blokk")
        print("route hozzáadva ✓")

    # 3) szintaxis-gyorsellenőrzés
    tmp = Path("/tmp/cortex_subs_check.mjs")
    tmp.write_text(src, encoding="utf-8")
    import subprocess
    chk = subprocess.run(["node", "--check", str(tmp)], capture_output=True, text=True)
    if chk.returncode != 0:
        print(chk.stderr[:400])
        raise SystemExit("SZINTAXIS HIBA — nem töltök fel")

    # 4) backup + upload (a bevált minta szerint)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    BACKUP.mkdir(parents=True, exist_ok=True)
    (BACKUP / f"{stamp}-before-subs.worker.js").write_text(src, encoding="utf-8")
    print("backup:", f"{stamp}-before-subs.worker.js")

    settings = requests.get(f"{API}/settings", headers=H, timeout=60).json()["result"]
    bindings = []
    for b in settings["bindings"]:
        if b["type"] == "secret_text":
            continue
        keep = {"name": b["name"], "type": b["type"]}
        for key in ("namespace_id", "bucket_name", "database_id", "id", "class_name"):
            if b.get(key):
                keep[key] = b[key]
        bindings.append(keep)
    metadata = {
        "main_module": "worker.js",
        "compatibility_date": settings.get("compatibility_date") or "2024-08-06",
        "compatibility_flags": settings.get("compatibility_flags") or [],
        "usage_model": settings.get("usage_model") or "standard",
        "bindings": bindings,
        "keep_bindings": ["secret_text"],
    }
    files = {
        "metadata": (None, json.dumps(metadata), "application/json"),
        "worker.js": ("worker.js", src.encode("utf-8"), "application/javascript+module"),
    }
    r = requests.put(API, headers=H, files=files, timeout=300)
    print("upload:", r.status_code, r.text[:200])
    r.raise_for_status()

    sched = requests.get(f"{API}/schedules", headers=H, timeout=60).json()["result"]
    print("cronok:", [s["cron"] for s in sched.get("schedules", [])])
    print("KÉSZ ✓")


if __name__ == "__main__":
    main()
