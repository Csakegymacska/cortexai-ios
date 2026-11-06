#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/phantom_constitution.py — Constitutional-AI-stílusú tanítóadat-gyártás.

A nyilvános Anthropic módszer (Constitutional AI, 2022 + Claude's character,
2024) magyar adaptációja a Cortex Phantom Core-hoz:

  SL-CAI  — a modell választ ír, a konstíció véletlen elve alapján önmagát
            kritizálja, és javított választ ír. A „javított" válasz megy az
            SFT-adatba (messages formátum).
  RLAIF   — ugyanarra a promptra két válasz készül, a modell az elvek alapján
            megrendezzi őket → preferencia-párok (prompt/chosen/rejected) DPO-hoz.

Módok:
  python3 tools/phantom_constitution.py --mode synth --prompts 20      # szintetikus kör
  python3 tools/phantom_constitution.py --mode revise \\
      --input cortex-phantom/data/corpus/sample-train.jsonl --limit 30  # meglévő párok javítása

Kimenet (alapból /var/tmp/phantom-cortex/): sl-cai.jsonl · prefs.jsonl · report.json
"""
from __future__ import annotations

import argparse
import json
import random
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path("/home/user")
sys.path.insert(0, str(ROOT / "tools"))
from ai_translate import call_gemini  # noqa: E402

CONSTITUTION_PATH = ROOT / "cortex-phantom/CORTEX-KONSTICIO.md"

SEED_TOPICS = [
    "Egy anime-szereplő bemutatkozik a barátainak egy táborban.",
    "Egy felirat-sor, amiben a főszereplő elbúcsúzik a testvérétől.",
    "Magyarázd el röviden, mi az a kvantum-összefonódás egy középiskolásnak.",
    "Adj tanácsot valakinek, aki most kezd el anime-feliratot fordítani.",
    "Egy harci jelenet párbeszéde két rivális között, tiszteletteljes hangon.",
    "Egy humoros pillanat a suliból, diákszlenggel.",
    "Hogyan készítsünk finom rántottát? Lépésről lépésre, röviden.",
    "Egy híradós bejelentés egy új animációs filmről.",
    "Bátorítsd azt, aki feladná a nyelvtanulást.",
    "Egy bölcs tanár tanácsa egy vizsga előtt álló diáknak.",
    "Írj egy rövid párbeszédet egy macskáról, aki megtanul beszélni.",
    "Egy sci-fi űrhajó kapitányának utasítása a legénységhez viharban.",
    "Magyarázd el, mitől jó egy fordítás — három pontban.",
    "Egy szomorú, de reményt keltő levél egy távoli baráthoz.",
    "Egy játékbeli küldetés leírása fantasy környezetben.",
    "Egy kávézói beszélgetés két régi barát között tíz év után.",
    "Egy edző motivációs beszéde a döntő előtt.",
    "Mesélj el egy rövid tanmesét a türelemről.",
    "Egy technikai hiba elmagyarázása egyszerűen, egy nagymamának.",
    "Egy szerelmi vallomás félénk szereplőtől, irodalmi stílusban.",
    "Egy anime-epizód összefoglalója két mondatban.",
    "Egy orvos megnyugtató válasza egy aggódó betegnek.",
    "Egy vicces félreértés a telefonban, két idegen között.",
    "Egy kósza harcos naplóbejegyzése egy elveszett városról.",
    "Magyarázd el a fotoszintézist egy tízévesnek, példákkal.",
    "Egy búcsúzó tanár utolsó mondatai az osztályhoz.",
    "Egy sci-fi android kérdése az emberi érzelmekről.",
    "Egy sürgős rádióüzenet egy eltűnt expedícióról.",
    "Egy kisgyerek kérdése az éjszakai égboltról, és a szülő válasza.",
    "Egy mesterember tanácsa a tanoncának az első munkanapon.",
]


def load_constitution() -> list[str]:
    text = CONSTITUTION_PATH.read_text(encoding="utf-8")
    principles = []
    for m in re.finditer(r"^(\d+)\.\s+\*\*(.+?)\*\*\s*(.*)$", text, re.M):
        body = (m.group(2) + " — " + m.group(3)).strip()
        principles.append(re.sub(r"\s+", " ", body))
    return principles


def jp(s: str) -> str:
    return re.sub(r"^```(?:json)?|```$", "", s.strip(), flags=re.M).strip()


def gen_response(prompt: str, temperature: float) -> str:
    out = call_gemini(
        "Te a Cortex nevű magyar AI-asszisztens vagy. Természetes, beszélt "
        "magyaron válaszolsz, tömören és életszerűen, töltelékszavak nélkül.",
        prompt, max_tokens=700, temperature=temperature,
    )
    return (out or "").strip()


def judge_pair(prompt: str, a: str, b: str, principle: str) -> str:
    """A konstíció egy elve alapján melyik válasz a jobb? 'A' vagy 'B'."""
    out = call_gemini(
        "Te egy nyelvi bíró vagy. Ítéld meg, melyik válasz felel meg jobban az "
        "adott elvnek. CSAK egy betűt írj: A vagy B.",
        f"ELV: {principle}\n\nKÉRDÉS: {prompt}\n\nVÁLASZ A:\n{a}\n\nVÁLASZ B:\n{b}",
        max_tokens=8, temperature=0.0,
    )
    up = (out or "").upper()
    if "A" in up and "B" not in up:
        return "A"
    if "B" in up and "A" not in up:
        return "B"
    return random.choice(["A", "B"])


def critique_and_revise(prompt: str, response: str, principle: str) -> tuple[str, str]:
    """SL-CAI lépés: kritika + javított válasz. (kritika, javított) jön vissza."""
    out = call_gemini(
        "Te a Cortex nevű magyar AI-asszisztens vagy. Előbb egy mondatban "
        "kritizáld a választ az ELV alapján (K: ...), majd írd át úgy, hogy "
        "tökéletesen megfeleljen neki. A formátum szigorú:\n"
        "K: <egy mondat kritika>\nJ: <javított válasz>",
        f"ELV: {principle}\n\nKÉRDÉS: {prompt}\n\nVÁLASZ:\n{response}",
        max_tokens=800, temperature=0.3,
    )
    out = out or ""
    mk = re.search(r"^K:\s*(.+)$", out, re.M)
    mj = re.search(r"^J:\s*(.+)$", out, re.M | re.S)
    crit = mk.group(1).strip() if mk else ""
    rev = mj.group(1).strip() if mj else out.strip()
    return crit, rev


def synth_pair(prompt: str, principles: list[str]) -> dict | None:
    try:
        a = gen_response(prompt, 0.4)
        b = gen_response(prompt, 0.9)
        if not a or not b or a == b:
            return None
        principle = random.choice(principles)
        winner = judge_pair(prompt, a, b, principle)
        chosen, rejected = (a, b) if winner == "A" else (b, a)
        crit, revised = critique_and_revise(prompt, chosen, principle)
        return {
            "prompt": prompt, "chosen": chosen, "rejected": rejected,
            "revised": revised, "critique": crit, "principle": principle[:160],
        }
    except Exception as e:  # noqa: BLE001
        print(f"    hiba: {str(e)[:80]}", flush=True)
        return None


def revise_pair(messages: list[dict], principles: list[str]) -> dict | None:
    try:
        prompt = messages[0]["content"]
        base = messages[-1]["content"]
        principle = random.choice(principles)
        crit, revised = critique_and_revise(prompt, base, principle)
        if not revised or revised == base:
            return None
        return {"prompt": prompt, "base": base, "revised": revised,
                "critique": crit, "principle": principle[:160]}
    except Exception as e:  # noqa: BLE001
        print(f"    hiba: {str(e)[:80]}", flush=True)
        return None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["synth", "revise"], default="synth")
    ap.add_argument("--prompts", type=int, default=20)
    ap.add_argument("--input", type=str, default=None)
    ap.add_argument("--limit", type=int, default=30)
    ap.add_argument("--out", type=str, default="/var/tmp/phantom-cortex")
    ap.add_argument("--workers", type=int, default=3)
    a = ap.parse_args()

    principles = load_constitution()
    print(f"konstíció: {len(principles)} elv betöltve")
    assert len(principles) >= 20, "a konstíció nem olvasható rendesen"

    outdir = Path(a.out)
    outdir.mkdir(parents=True, exist_ok=True)
    t0 = time.time()

    if a.mode == "synth":
        seeds = random.sample(SEED_TOPICS, min(a.prompts, len(SEED_TOPICS)))
        print(f"szintetikus kör: {len(seeds)} prompt")
        results = []
        with ThreadPoolExecutor(max_workers=a.workers) as pool:
            for r in pool.map(lambda p: synth_pair(p, principles), seeds):
                if r:
                    results.append(r)
        sft = [{"messages": [
            {"role": "user", "content": r["prompt"]},
            {"role": "assistant", "content": r["revised"]},
        ]} for r in results]
        prefs = [{"prompt": r["prompt"], "chosen": r["chosen"],
                  "rejected": r["rejected"], "principle": r["principle"]}
                 for r in results]
    else:
        data = [json.loads(x) for x in Path(a.input).read_text(encoding="utf-8").splitlines() if x.strip()]
        data = data[:a.limit]
        print(f"javító kör: {len(data)} meglévő pár")
        results = []
        with ThreadPoolExecutor(max_workers=a.workers) as pool:
            for r in pool.map(lambda d: revise_pair(d["messages"], principles), data):
                if r:
                    results.append(r)
        sft = [{"messages": [
            {"role": "user", "content": r["prompt"]},
            {"role": "assistant", "content": r["revised"]},
        ]} for r in results]
        prefs = [{"prompt": r["prompt"], "chosen": r["revised"],
                  "rejected": r["base"], "principle": r["principle"]}
                 for r in results]

    (outdir / "sl-cai.jsonl").write_text(
        "\n".join(json.dumps(x, ensure_ascii=False) for x in sft) + "\n", encoding="utf-8")
    (outdir / "prefs.jsonl").write_text(
        "\n".join(json.dumps(x, ensure_ascii=False) for x in prefs) + "\n", encoding="utf-8")
    report = {
        "mode": a.mode, "principles": len(principles),
        "in": a.prompts if a.mode == "synth" else a.limit,
        "sft_pairs": len(sft), "pref_pairs": len(prefs),
        "seconds": round(time.time() - t0, 1),
    }
    (outdir / "report.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
