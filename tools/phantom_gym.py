#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/phantom_gym.py — agentic edzőterem a Cortex Phantom Core-nak.

A felhasználó kérése (2026-11-06): „adsz neki környezetet és adsz neki
feladatot" — a modell eszközökkel dolgozik a feladaton, a végén jutalmat kap,
és a jó trajektoriák tanítóadattá válnak (agentic SFT + preferencia-párok).

Környezet (eszközök):
  calc          — biztonságos számítás
  corpus_search — keresés a saját korpuszban (katalógus-QA + minták)
  hu_check      — magyar szöveg minőségi ellenőrzése (FineWeb-heurisztika)
  subtitle_get  — valódi felirat-sor a saját epizódokból (subs/)

Feladattípusok: számítás · tudás-kérdés (eszközzel!) · felirat-javítás ·
összefoglalás. Minden kör végén a konstíció elvei szerinti pontozás is fut.

  python3 tools/phantom_gym.py --tasks 16
Kimenet: /var/tmp/phantom-gym/{gym-sft.jsonl, gym-prefs.jsonl, report.json}
"""
from __future__ import annotations

import argparse
import json
import random
import re
import sys
import time
from pathlib import Path

ROOT = Path("/home/user")
sys.path.insert(0, str(ROOT / "tools"))
from ai_translate import call_gemini, call_glm45  # noqa: E402


def chat(system: str, user: str, max_tokens: int = 800, temperature: float = 0.3) -> str:
    try:
        return call_gemini(system, user, max_tokens=max_tokens, temperature=temperature)
    except Exception:  # noqa: BLE001
        return call_glm45(system, user, max_tokens=max_tokens, temperature=temperature)
from phantom_quality import score_pair  # noqa: E402
from phantom_constitution import load_constitution  # noqa: E402

SYSTEM = (
    "Te a Cortex nevű magyar AI-asszisztens vagy, és egy feladatot oldasz meg "
    "eszközökkel. Minden lépésben CSAK EGY JSON-t írj, mást ne:\n"
    '{"action": {"tool": "<név>", "args": {…}}}  — ha eszközt használsz, VAGY\n'
    '{"answer": "<végleges válasz>"}  — ha kész vagy.\n'
    "Elérhető eszközök:\n"
    "- calc: {\"expr\": \"számítás\"} — alapműveletek\n"
    "- corpus_search: {\"query\": \"keresés\"} — keresés a saját tudásbázisban\n"
    "- hu_check: {\"text\": \"szöveg\"} — magyar szöveg minőségi ellenőrzése\n"
    "- subtitle_get: {\"aid\": 170113, \"ep\": 1, \"n\": 3} — felirat-sor az epizódból\n"
    "Maximum 3 eszközlépés, utána kötelező válaszolni."
)

ENV_DESC = "Környezet: Cortex Gym — eszközök: calc, corpus_search, hu_check, subtitle_get."


# ── eszközök ────────────────────────────────────────────────────────────────

def tool_calc(args: dict) -> str:
    expr = str(args.get("expr", ""))
    if not re.fullmatch(r"[\d\s+\-*/().%]+", expr):
        return "HIBA: csak számok és + - * / ( ) % engedélyezett"
    try:
        return str(eval(expr, {"__builtins__": {}}, {}))  # noqa: S307 - fent szűrve
    except Exception as e:  # noqa: BLE001
        return f"HIBA: {e}"


def _corpus_rows() -> list[dict]:
    rows = []
    for name in ("catalog-qa.jsonl", "sample-train.jsonl"):
        p = ROOT / "cortex-phantom/data/corpus" / name
        if p.exists():
            rows += [json.loads(x) for x in p.read_text(encoding="utf-8").splitlines() if x.strip()]
    return rows


CORPUS = _corpus_rows()


def tool_corpus_search(args: dict) -> str:
    q = str(args.get("query", "")).lower()
    if not q:
        return "HIBA: üres keresés"
    qt = set(re.findall(r"\w+", q, re.UNICODE))
    best = []
    for row in CORPUS:
        msgs = row.get("messages", [])
        text = " ".join(m.get("content", "") for m in msgs)
        tt = set(re.findall(r"\w+", text.lower(), re.UNICODE))
        overlap = len(qt & tt)
        if overlap:
            best.append((overlap, text[:220]))
    best.sort(key=lambda x: -x[0])
    return "\n---\n".join(t for _, t in best[:2]) or "Nincs találat."


def tool_hu_check(args: dict) -> str:
    text = str(args.get("text", ""))
    score, issues = score_pair("", text)
    return json.dumps({"pont": score, "hibak": issues}, ensure_ascii=False)


def tool_subtitle_get(args: dict) -> str:
    aid, ep, n = int(args.get("aid", 0)), int(args.get("ep", 0)), int(args.get("n", 1))
    p = ROOT / "subs" / str(aid) / f"{ep}.hu.vtt"
    if not p.exists():
        return "HIBA: nincs ilyen epizód"
    cues = [c for c in p.read_text(encoding="utf-8").split("\n\n") if "-->" in c]
    if not 1 <= n <= len(cues):
        return f"HIBA: nincs {n}. sor (összesen {len(cues)})"
    return cues[n - 1].splitlines()[-1]


TOOLS = {
    "calc": tool_calc,
    "corpus_search": tool_corpus_search,
    "hu_check": tool_hu_check,
    "subtitle_get": tool_subtitle_get,
}


# ── feladatok ───────────────────────────────────────────────────────────────

def make_tasks(n: int) -> list[dict]:
    tasks = []
    for i in range(n):
        kind = ["calc", "qa", "fix", "summary"][i % 4]
        if kind == "calc":
            a, b, op = random.randint(12, 99), random.randint(3, 29), random.choice("+-*")
            expr = f"{a}{op}{b}"
            ans = str(eval(expr))  # noqa: S307
            tasks.append({
                "type": "calc", "check": {"exact": ans},
                "prompt": f"Számold ki a következőt a calc eszközzel, lépésben: {expr}",
            })
        elif kind == "qa":
            row = random.choice([r for r in CORPUS if len(r.get("messages", [])) >= 2])
            q = row["messages"][0]["content"][:140]
            a = row["messages"][1]["content"][:120]
            tasks.append({
                "type": "qa", "check": {"keywords": re.findall(r"\w+", a.lower())[:6]},
                "prompt": f"Válaszolj a kérdésre, és ELŐBB keress a corpus_search eszközzel: {q}",
            })
        elif kind == "fix":
            bad = random.choice([
                "This is a very good thing that we are doing here today together.",
                "I do not know what is the problem with this situation right now.",
                "The cat is sitting on the table and looking at the window very much.",
            ])
            tasks.append({
                "type": "fix", "check": {"llm": "A javított szöveg természetes, magyar, gépies fordításra emlékeztető hibák nélküli legyen."},
                "prompt": f"Javítsd fel ezt a gépies magyar fordítást természetes magyarra. Előbb ellenőrizd a hu_check eszközzel, aztán javíts: {bad}",
            })
        else:
            aid = random.choice([170113, 159808])
            tasks.append({
                "type": "summary", "check": {"llm": "Az összefoglaló 1-2 mondat, magyar, és visszaadja a lényeget."},
                "prompt": f"Olvasd be a subtitle_get eszközzel a(z) {aid} epizód 1. részének 2., 3. és 4. felirat-sorát (ep=1, n=2/3/4), majd foglald össze 1-2 mondatban, miről szól.",
            })
    return tasks


# ── környezeti hurok ────────────────────────────────────────────────────────

def parse_action(text: str) -> dict:
    m = re.search(r"\{.*\}", text, re.S)
    if not m:
        return {"answer": text.strip()}
    try:
        d = json.loads(m.group(0))
    except Exception:  # noqa: BLE001
        return {"answer": text.strip()}
    return d if ("action" in d or "answer" in d) else {"answer": text.strip()}


def run_episode(task: dict, principles: list[str]) -> dict | None:
    messages = [{"role": "user", "content": task["prompt"]}]
    trajectory = []
    answer = ""
    try:
        for _ in range(4):
            user_block = ENV_DESC + "\n\n" + "\n".join(
                f"[{m['role']}] {m['content']}" for m in messages[-6:])
            out = chat(SYSTEM, user_block, max_tokens=400, temperature=0.3)
            d = parse_action(out or "")
            if "answer" in d:
                answer = str(d["answer"])
                break
            act = d.get("action") or {}
            name, args = act.get("tool"), act.get("args") or {}
            if name not in TOOLS:
                obs = f"HIBA: nincs ilyen eszköz: {name}"
            else:
                obs = TOOLS[name](args)
            trajectory.append({"tool": name, "args": args, "obs": str(obs)[:300]})
            messages.append({"role": "user", "content": f"[eszköz eredménye] {obs}"})
        if not answer:
            return None

        # ellenőrzés: pontos + konstíció-bíró
        check = task.get("check", {})
        ok = 0.5
        if "exact" in check:
            ok = 1.0 if check["exact"] in answer.replace(" ", "") else 0.0
        elif "keywords" in check:
            hit = sum(1 for w in check["keywords"] if w in answer.lower())
            ok = hit / max(1, len(check["keywords"]))
        verdict = chat(
            "Te a Cortex konstíció bírája vagy. Pontozd a választ 0-5-ig CSAK EGY "
            "SZÁMMAL a feladatra való alkalmasság és a termesség szerint.",
            f"FELADAT: {task['prompt']}\n\nVÁLASZ: {answer[:600]}", max_tokens=8, temperature=0.0)
        m = re.search(r"[0-5]", verdict or "")
        judge = (int(m.group(0)) / 5.0) if m else 0.5
        reward = round(0.5 * ok + 0.5 * judge, 3)
        return {"task": task, "answer": answer, "trajectory": trajectory,
                "reward": reward, "exact_ok": ok, "judge": judge}
    except Exception as e:  # noqa: BLE001
        print(f"    hiba ({task['type']}): {str(e)[:70]}", flush=True)
        return None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tasks", type=int, default=16)
    ap.add_argument("--out", default="/var/tmp/phantom-gym")
    a = ap.parse_args()

    principles = load_constitution()
    outdir = Path(a.out)
    outdir.mkdir(parents=True, exist_ok=True)
    t0 = time.time()

    tasks = make_tasks(a.tasks)
    print(f"gym: {len(tasks)} feladat · {len(principles)} elv · {len(CORPUS)} korpusz-sor")
    results = []
    for t in tasks:
        r = run_episode(t, principles)
        if r:
            results.append(r)
            print(f"  [{t['type']:8s}] reward={r['reward']} · lépés={len(r['trajectory'])}")

    # SFT: a jutalmazott trajektoriák teljes üzenetfolyamként
    sft = []
    for r in results:
        if r["reward"] < 0.5:
            continue
        msgs = [{"role": "system", "content": SYSTEM},
                {"role": "user", "content": r["task"]["prompt"]}]
        for step in r["trajectory"]:
            msgs.append({"role": "assistant", "content": json.dumps({"action": {"tool": step["tool"], "args": step["args"]}}, ensure_ascii=False)})
            msgs.append({"role": "user", "content": f"[eszköz eredménye] {step['obs']}"})
        msgs.append({"role": "assistant", "content": json.dumps({"answer": r["answer"]}, ensure_ascii=False)})
        sft.append({"messages": msgs, "reward": r["reward"], "type": r["task"]["type"]})

    # preferencia-párok: azonos típuson belül jobb vs. rosszabb
    prefs = []
    by_type: dict[str, list] = {}
    for r in results:
        by_type.setdefault(r["task"]["type"], []).append(r)
    for typ, rs in by_type.items():
        rs.sort(key=lambda x: -x["reward"])
        if len(rs) >= 2 and rs[0]["reward"] > rs[-1]["reward"]:
            prefs.append({"prompt": rs[0]["task"]["prompt"],
                          "chosen": rs[0]["answer"], "rejected": rs[-1]["answer"],
                          "principle": "agentic: pontos eszközhasználat és helyes válasz"})

    (outdir / "gym-sft.jsonl").write_text("\n".join(json.dumps(x, ensure_ascii=False) for x in sft) + "\n", encoding="utf-8")
    (outdir / "gym-prefs.jsonl").write_text("\n".join(json.dumps(x, ensure_ascii=False) for x in prefs) + "\n", encoding="utf-8")
    report = {"tasks": len(tasks), "episodes": len(results),
              "avg_reward": round(sum(r["reward"] for r in results) / max(1, len(results)), 3),
              "sft": len(sft), "prefs": len(prefs),
              "by_type": {k: round(sum(x["reward"] for x in v) / len(v), 2) for k, v in by_type.items()},
              "seconds": round(time.time() - t0, 1)}
    (outdir / "report.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
