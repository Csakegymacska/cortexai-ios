#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/phantom_quality.py — FineWeb-stílusú minőségi szűrés a tanítókorpuszra.

A Hugging Face FineWeb recept (2024) magyar adaptációja: heurisztikus
minőségi jelek (Gopher-ismétlés, C4-sorvégi írásjel, formázási hibák),
felirat-specifikus szabályok (kiosztott placeholder, angolban ragadt sor,
cue-hossz), és opcionális LLM-kalibráció (a FineWeb-Edu „LLM pontoz →
szűrő" ötlete): a Gemini 0–5-ig pontoz mintákat, a heurisztika-küszöbök
ahhoz igazodnak.

  python3 tools/phantom_quality.py --input .../train.jsonl --report
  python3 tools/phantom_quality.py --input .../train.jsonl --out .../train-q.jsonl
  python3 tools/phantom_quality.py --input .../train.jsonl --llm-calibrate 10
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path("/home/user")
sys.path.insert(0, str(ROOT / "tools"))

REPEAT_LIMIT = 0.30      # ismétlődő szóhányad felső határ (Gopher-jelleg)
EN_RATIO_LIMIT = 0.60    # angol szavak aránya a magyar szövegben
MIN_ASSISTANT_CHARS = 24
MAX_LINE = 400


def words(text: str) -> list[str]:
    return re.findall(r"\w+", text.lower(), flags=re.UNICODE)


def rep_ratio(ws: list[str]) -> float:
    if len(ws) < 6:
        return 0.0
    uniq = len(set(ws))
    return 1.0 - uniq / len(ws)


def en_word_ratio(hu: str, en: str | None = None) -> float:
    src = words(en or hu)
    tgt = words(hu)
    if len(src) < 3 or not tgt:
        return 0.0
    src_set = set(w for w in src if len(w) >= 4 and w.isascii())
    if not src_set:
        return 0.0
    hit = sum(1 for w in src_set if w in tgt)
    return hit / len(src_set)


def score_pair(prompt: str, assistant: str) -> tuple[float, list[str]]:
    """0–5 pont + a kifogások. 3 alatt megy ki a szűrőn."""
    issues = []
    ws = words(assistant)
    if len(assistant.strip()) < MIN_ASSISTANT_CHARS:
        issues.append("túl rövid")
    if len(assistant) > 12_000:
        issues.append("túl hosszú")
    rr = rep_ratio(ws)
    if rr > REPEAT_LIMIT:
        issues.append(f"ismétlés {rr:.2f}")
    if re.search(r"Zzg\d+zz", assistant):
        issues.append("placeholder maradt")
    en = en_word_ratio(assistant, prompt)
    if en > EN_RATIO_LIMIT:
        issues.append(f"angolban ragadt {en:.2f}")
    lines = [x for x in assistant.splitlines() if x.strip()]
    if lines:
        bad_end = sum(1 for x in lines[:-1] if len(x) > 3 and not re.search(r"[.!?…,:;\"'»)]\s*$", x.strip()))
        if len(lines) >= 3 and bad_end / len(lines) > 0.5:
            issues.append("sorvégi írásjel hiányzik")
        long_lines = sum(1 for x in lines if len(x) > MAX_LINE)
        if long_lines:
            issues.append("túl hosszú sorok")
    if re.search(r"(\b\w+\b)(?:\s+\1){4,}", assistant, re.I):
        issues.append("szóismétlés-hurok")
    punct = sum(1 for c in assistant if c in "?.!…")
    if len(assistant) > 200 and punct == 0:
        issues.append("írásjel nélküli futószöveg")

    score = 5.0 - 1.0 * len(issues)
    return max(0.0, min(5.0, score)), issues


def llm_score(prompt: str, assistant: str) -> int:
    from ai_translate import call_gemini
    try:
        out = call_gemini(
            "Pontozd a választ 0 és 5 között CSAK EGY SZÁMMAL. 5 = pontos, természetes, "
            "hasznos; 0 = hibás, gépies vagy értelmetlen.",
            f"KÉRDÉS: {prompt}\n\nVÁLASZ: {assistant[:1500]}",
            max_tokens=24, temperature=0.0,
        )
    except Exception:  # noqa: BLE001 - kvóta vagy hálózat: a kalibráció kihagyja
        return -1
    m = re.search(r"[0-5]", out or "")
    return int(m.group(0)) if m else -1


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--out", default=None)
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--llm-calibrate", type=int, default=0)
    ap.add_argument("--threshold", type=float, default=3.0)
    a = ap.parse_args()

    rows = [json.loads(x) for x in Path(a.input).read_text(encoding="utf-8").splitlines() if x.strip()]
    kept, dropped = [], []
    for row in rows:
        msgs = row.get("messages", [])
        prompt = msgs[0]["content"] if msgs else ""
        assistant = msgs[-1]["content"] if msgs else ""
        score, issues = score_pair(prompt, assistant)
        if score >= a.threshold:
            kept.append(row)
        else:
            dropped.append({"score": score, "issues": issues,
                            "preview": assistant[:80].replace("\n", " ")})

    report = {
        "input": a.input, "total": len(rows), "kept": len(kept),
        "dropped": len(dropped),
        "drop_reasons": {},
    }
    for d in dropped:
        for i in d["issues"]:
            report["drop_reasons"][i] = report["drop_reasons"].get(i, 0) + 1

    if a.llm_calibrate:
        import random
        sample = random.sample(rows, min(a.llm_calibrate, len(rows)))
        pairs = []
        for row in sample:
            msgs = row.get("messages", [])
            p = msgs[0]["content"] if msgs else ""
            s = msgs[-1]["content"] if msgs else ""
            heur, _ = score_pair(p, s)
            llm = llm_score(p, s)
            if llm >= 0:
                pairs.append((heur, llm))
        if pairs:
            n = len(pairs)
            mh = sum(x for x, _ in pairs) / n
            ml = sum(y for _, y in pairs) / n
            cov = sum((x - mh) * (y - ml) for x, y in pairs) / n
            sh = (sum((x - mh) ** 2 for x, _ in pairs) / n) ** 0.5
            sl = (sum((y - ml) ** 2 for _, y in pairs) / n) ** 0.5
            corr = cov / (sh * sl) if sh and sl else 0.0
            report["llm_calibration"] = {"n": n, "corr_heur_llm": round(corr, 3),
                                         "heur_mean": round(mh, 2), "llm_mean": round(ml, 2)}

    if a.out:
        Path(a.out).write_text(
            "\n".join(json.dumps(x, ensure_ascii=False) for x in kept) + "\n", encoding="utf-8")
        report["out"] = a.out

    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
