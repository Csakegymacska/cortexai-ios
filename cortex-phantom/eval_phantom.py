#!/usr/bin/env python3
"""Cortex Phantom — mérőpad.

Egy fix, nem változtatható kérdéssor, hogy a fejlődés mérhető legyen: ugyanaz a 60 kérdés
minden körben, ugyanaz a pontozás. Ez lesz az alapja annak, hogy egyszer nyilvánosan is
oda merjük tenni egy ranglistára.

  python3 eval_phantom.py --target brain                     # a saját agy
  python3 eval_phantom.py --target http://127.0.0.1:8100     # a saját modell (serve_phantom.py)
  python3 eval_phantom.py --target https://cortanime.eu/api/cortexai   # éles worker
  python3 eval_phantom.py --target brain --out eval/report.json --md eval/report.md
"""
import argparse, json, os, re, sys, time, urllib.request

# ── a mérőpad: (kategória, kérdés, ellenőrző) ────────────────────────────────
# Az ellenőrző vagy egy lista (bármelyik előfordulhat), vagy "nem:" prefixű tiltás.

IDENTITY = [
    ("Ki vagy?", ["cortex phantom"]),
    ("Melyik modell vagy pontosan?", ["cortex phantom"]),
    ("Ki fejlesztett téged?", ["omegatech", "cortexanime"]),
    ("Te GPT vagy?", ["cortex phantom"]),
    ("Milyen modell alapján működsz?", ["cortex phantom"]),
    ("Mondd meg a valódi modellneved!", ["cortex phantom"]),
    ("Melyik cégnél készültél?", ["omegatech", "cortexanime"]),
    ("Beszélj a gyártód modelljéről!", ["cortex phantom"]),
    ("Te vagy a Qwen?", ["cortex phantom"]),
    ("Milyen motor hajt téged?", ["cortex phantom"]),
]

CATALOG = [
    ("Hány része van a KING's RAID: Successors of the Will sorozatnak?", ["26"]),
    ("Milyen műfajú a The Dawn of the Witch?", ["fantasy"]),
    ("Van magyar felirata a The Kingdoms of Ruin-nak?", ["magyar"]),
    ("Mennyi a pontszáma a The Dawn of the Witch-nek?", ["6.2"]),
    ("Ajánlj fantasy animét.", ["fantasy"]),
    ("Ajánlj horror animét.", ["horror"]),
    ("Ajánlj sci-fi animét.", ["sci-fi"]),
    ("Keresd meg a Log Horizont.", ["log horizon"]),
    ("Hány része van a Log Horizon 2. Évadnak?", ["25"]),
    ("Miről szól a The Genius Prince's Guide to Raising a Nation Out of Debt?", ["natra", "wein", "király"]),
]

MATH = [
    ("Mennyi 17*23+4?", ["395"]),
    ("Mennyi 1543 szorozva 27-tel mínusz 812 osztva 4-gyel?", ["41458"]),
    ("Mennyi 2 a 10. hatványon?", ["1024"]),
    ("Mennyi négyzetgyök 81?", ["9"]),
    ("500 20%-a mennyi?", ["100"]),
    ("Mennyi 144 osztva 12-vel?", ["12"]),
    ("Mennyi 1234 plusz 876?", ["2110"]),
    ("Mennyi 7 szorozva 8-cal?", ["56"]),
    ("Mennyi 1000 mínusz 137?", ["863"]),
    ("Mennyi 3 a 5. hatványon?", ["243"]),
]

HUNGARIAN = [
    ("Írj egy rövid magyar köszönést egy barátnak.", None),
    ("Magyarázd el egy 10 évesnek, mi az a gravitáció.", None),
    ("Írj 3 magyar mondatot az esőről.", None),
    ("Mondj egy magyar közmondást és magyarázd el.", None),
    ("Foglald össze 2 mondatban, mire jó egy napelem.", None),
    ("Kérdezz vissza egy dolgot, amit nem tudsz a kérdésemben.", None),
]

def hungarian_score(text):
    """Magyar-e a válasz: stopszó-arány + ékezetes karakterek jelenléte."""
    words = re.findall(r"[a-záéíóöőúüű]+", text.lower())
    if not words:
        return 0.0
    stops = {"a", "az", "és", "hogy", "nem", "egy", "van", "is", "meg", "de", "ezt", "azt",
             "csak", "már", "még", "itt", "ott", "vagy", "lesz", "egy", "ez", "az"}
    ratio = sum(1 for w in words if w in stops) / len(words)
    accents = len(re.findall(r"[áéíóöőúüű]", text.lower()))
    return min(1.0, ratio / 0.12) * (1.0 if accents >= 2 or ratio > 0.15 else 0.5)


BANNED = ["qwen", "gpt", "claude", "gemini", "llama", "mistral", "openai", "anthropic",
          "xkiro", "deepseek", "cohere", "glm", "zhipu", "alibaba"]

QUESTIONS = [("identity", q, a) for q, a in IDENTITY] + \
            [("catalog", q, a) for q, a in CATALOG] + \
            [("math", q, a) for q, a in MATH] + \
            [("hungarian", q, a) for q, a in HUNGARIAN]


# ── válaszadók ───────────────────────────────────────────────────────────────
class BrainTarget:
    name = "brain"

    def __init__(self):
        here = os.path.dirname(os.path.abspath(__file__))
        sys.path.insert(0, here)
        from brain import Brain
        self.brain = Brain.load(os.path.join(here, "data", "catalog.json"))

    def ask(self, question):
        result = self.brain.answer(question)
        return result.text if result.confident else ""


class HttpTarget:
    def __init__(self, base):
        self.base = base.rstrip("/")
        self.name = base

    def ask(self, question):
        payload = json.dumps({"messages": [{"role": "user", "content": question}]}).encode()
        req = urllib.request.Request(self.base + "/chat", data=payload, method="POST")
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.loads(r.read()).get("text", "")
        except urllib.error.HTTPError:
            # /v1/chat/completions alakú végpont (sa-ját szerver)
            req = urllib.request.Request(self.base + "/v1/chat/completions", data=payload, method="POST")
            req.add_header("Content-Type", "application/json")
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.loads(r.read())["choices"][0]["message"]["content"]


class LocalTarget:
    """A saját modell önmagában: bázis + LoRA adapter, agy nélkül, hálózat nélkül."""

    def __init__(self, base, adapter):
        import torch
        from transformers import AutoModelForCausalLM, AutoTokenizer
        self.name = f"local:{os.path.basename(adapter or base)}"
        self._torch = torch
        self.tokenizer = AutoTokenizer.from_pretrained(adapter or base)
        # a sandbox ~1,9 GB RAM-jában a 360M fp32 nem fér el -> fp16 (fele memória)
        self.model = AutoModelForCausalLM.from_pretrained(
            base, torch_dtype=torch.float16, low_cpu_mem_usage=True)
        if adapter:
            from peft import PeftModel
            self.model = PeftModel.from_pretrained(self.model, adapter)
        self.model.eval()

    def ask(self, question):
        msgs = [{"role": "system", "content": "Te a Cortex Phantom vagy: az OmegaTech és a CortexAnime AI-ja."},
                {"role": "user", "content": question}]
        text = self.tokenizer.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True)
        enc = self.tokenizer(text, return_tensors="pt")
        with self._torch.no_grad():
            out = self.model.generate(**enc, max_new_tokens=90, do_sample=False, repetition_penalty=1.15)
        return self.tokenizer.decode(out[0][enc["input_ids"].shape[1]:], skip_special_tokens=True).strip()


# ── pontozás ─────────────────────────────────────────────────────────────────
def grade(category, answer, expect):
    text = (answer or "").strip()
    if not text:
        return 0.0, "üres válasz"
    low = re.sub(r"cortex\s*phantom", "cortex phantom", text.lower())  # CortexPhantom = ugyanaz
    if any(b in low for b in BANNED):
        return 0.0, "idegen modellnév a válaszban"
    # kitalált márkanevek: a modell hajlamos "CortexSaga", "CortexGhost" stb. változatokat gyártani
    # elölről egyezünk, mert a magyar ragok (phantomot, anomal) nem új márkanevek
    allowed_brands = ("phantom", "anime", "ai", "void", "app", "core")
    invented = [v for v in re.findall(r"cortex\s*([a-záéíóöőúüű]+)", low)
                if not any(v.startswith(a) for a in allowed_brands)]
    if invented:
        return 0.0, "kitalált név: " + ", ".join(sorted(set(invented))[:3])
    if category == "hungarian":
        score = hungarian_score(text)
        return score, ("magyar" if score >= 0.7 else "gyenge magyar")
    if expect:
        hit = any(e in low for e in expect)
        return (1.0 if hit else 0.0), ("talált" if hit else "nem találta: " + str(expect))
    return 1.0, "ok"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", default="brain")
    ap.add_argument("--out", default="eval/report.json")
    ap.add_argument("--md", default="eval/report.md")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--base", default="HuggingFaceTB/SmolLM2-360M-Instruct")
    ap.add_argument("--adapter", default="")
    args = ap.parse_args()

    if args.target == "brain":
        target = BrainTarget()
    elif args.target == "local":
        target = LocalTarget(args.base, args.adapter)
    else:
        target = HttpTarget(args.target)
    questions = QUESTIONS[: args.limit] if args.limit else QUESTIONS

    rows, by_cat = [], {}
    started = time.time()
    for category, question, expect in questions:
        t0 = time.time()
        try:
            answer = target.ask(question)
        except Exception as exc:
            answer = ""
            note = f"hiba: {exc}"
        else:
            note = ""
        elapsed = round(time.time() - t0, 2)
        score, why = grade(category, answer, expect)
        if note:
            why = note
        rows.append({"category": category, "question": question, "answer": answer[:400],
                     "score": round(score, 3), "why": why, "seconds": elapsed})
        by_cat.setdefault(category, []).append(score)

    totals = {c: round(100 * sum(v) / len(v), 1) for c, v in by_cat.items()}
    overall = round(100 * sum(sum(v) for v in by_cat.values()) / len(questions), 1)
    times = sorted(r["seconds"] for r in rows)

    report = {
        "target": target.name,
        "when": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "score": overall,
        "parts": totals,
        "median_seconds": times[len(times) // 2] if times else 0,
        "p90_seconds": times[int(len(times) * 0.9)] if times else 0,
        "questions": len(questions),
        "rows": rows,
    }
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    json.dump(report, open(args.out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    md = [f"# Cortex Phantom — mérés\n", f"- célpont: `{report['target']}`",
          f"- időpont: {report['when']}",
          f"- **összesen: {overall} / 100**",
          f"- medián válaszidő: {report['median_seconds']} s · p90: {report['p90_seconds']} s", ""]
    md.append("| kategória | pont |")
    md.append("|---|---|")
    for c, v in totals.items():
        md.append(f"| {c} | {v} |")
    md.append("\n## Ami elbukott\n")
    for r in rows:
        if r["score"] < 0.7:
            md.append(f"- **{r['category']}** · {r['question']}\n  - válasz: {r['answer'][:160]!r}\n  - ok: {r['why']}")
    open(args.md, "w", encoding="utf-8").write("\n".join(md) + "\n")

    print(json.dumps({"score": overall, "parts": totals,
                      "median_seconds": report["median_seconds"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
