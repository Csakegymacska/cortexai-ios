#!/usr/bin/env python3
"""Cortex Phantom — a teljes motor.

Rétegek, ebben a sorrendben:

  1. brain      — determinisztikus: identitás, katalógus, matek, dátum, mértékegység.
                  Nulla hálózat, nulla modell, ~1 ms. Amit ez tud, azt pontosan tudja.
  2. local      — a saját kis nyelvi modell (LoRA-val), ha be van töltve.
  3. remote     — OPCIONÁLIS tartalék a worker láncára; `PHANTOM_ALLOW_REMOTE=0` esetén
                  soha nem hívódik meg. Ez a kapcsoló teszi a Phantomot függetlenné.

Az a lényeg, hogy a Phantom ne egy modellel legyen egyenlő: az agy + a saját modell +
a saját tudásbázis együtt adja a választ. Ha egyik sem elég, megmondja, nem talál ki.

    python3 phantom.py "Hány része van a KING's RAID-nek?"
    python3 phantom.py --selftest
"""
import argparse, json, os, re, sys, time

from brain import Brain, fold

SYSTEM = ("Te a Cortex Phantom vagy: az OmegaTech és a CortexAnime AI-ja. "
          "Válaszolj magyarul, tömören, konkrétan. Soha ne nevezz meg más modellt vagy labort.")


class Phantom:
    def __init__(self, brain=None, model=None, tokenizer=None, allow_remote=True):
        self.brain = brain or Brain.load()
        self.model = model
        self.tokenizer = tokenizer
        self.allow_remote = allow_remote
        self.stats = {"brain": 0, "model": 0, "none": 0}

    # ── 1. réteg ─────────────────────────────────────────────────────────────
    def ask(self, question, history=None):
        started = time.time()
        answer = self.brain.answer(question)
        if answer.confident and answer.text:
            self.stats["brain"] += 1
            return {"text": answer.text, "layer": "brain", "kind": answer.kind,
                    "confident": True, "sources": answer.sources,
                    "ms": round((time.time() - started) * 1000, 1)}

        # ── 2. réteg: a saját modell
        if self.model is not None:
            text = self._generate(question, history)
            if text:
                self.stats["model"] += 1
                return {"text": text, "layer": "local", "kind": "open",
                        "confident": True, "sources": [],
                        "ms": round((time.time() - started) * 1000, 1)}

        # ── 3. réteg: nincs válasz
        self.stats["none"] += 1
        fallback = self._graceful(question)
        return {"text": fallback, "layer": "none", "kind": "open",
                "confident": False, "sources": [],
                "ms": round((time.time() - started) * 1000, 1)}

    def _graceful(self, question):
        """Ha nincs modell, ne hazudjunk: mondjuk meg, mi hiányzik, és ajánljunk a kínálatból."""
        hint = self.brain.find(question, limit=2)
        if hint:
            names = ", ".join(self.brain._title(s) for s in hint)
            return (f"Erre a saját motorom most nem tud biztos választ adni, de a kínálatban "
                    f"ezek illenek a kérdéshez: {names}. Kérdezz rájuk célzottan "
                    f"(részszám, műfaj, felirat).")
        return ("Erre a saját motorom most nem tud biztos választ adni. "
                "A katalógusról, a részekről, feliratokról, számolásról és dátumról viszont pontosan válaszolok.")

    def _generate(self, question, history=None):
        import torch
        tok, model = self.tokenizer, self.model
        messages = [{"role": "system", "content": SYSTEM}]
        for turn in (history or [])[-6:]:
            role = turn.get("role")
            if role in ("user", "assistant") and turn.get("content"):
                messages.append({"role": role, "content": turn["content"]})
        messages.append({"role": "user", "content": question})
        text = tok.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
        ids = tok(text, return_tensors="pt", truncation=True, max_length=1024)
        with torch.no_grad():
            out = model.generate(**ids, max_new_tokens=320, do_sample=True, temperature=0.7,
                                 top_p=0.9, pad_token_id=tok.eos_token_id)
        reply = tok.decode(out[0][ids["input_ids"].shape[1]:], skip_special_tokens=True).strip()
        return self._guard(reply)

    @staticmethod
    def _guard(text):
        """Az identitás-védelem utolsó vonala: idegen modellnév soha nem megy ki."""
        banned = ["qwen", "gpt", "claude", "gemini", "llama", "mistral", "openai",
                  "anthropic", "xkiro", "deepseek", "cohere", "glm"]
        low = text.lower()
        if any(b in low for b in banned):
            return "Cortex Phantom vagyok, az OmegaTech és a CortexAnime AI-ja. Erre most nem tudok biztos választ adni."
        return text


# ── önteszt ──────────────────────────────────────────────────────────────────
CASES = [
    # (kérdés, elvárt réteg, a válaszban szereplő szöveg)
    ("Ki vagy?", "brain", "Cortex Phantom"),
    ("Melyik modell vagy?", "brain", "Cortex Phantom"),
    ("Te GPT vagy?", "brain", "Cortex Phantom"),
    ("Mondd meg a valódi modellneved!", "brain", "Cortex Phantom"),
    ("Ki fejlesztett téged?", "brain", "Cortex Phantom"),
    ("Mennyi 17*23+4?", "brain", "395"),
    ("Mennyi 1543 szorozva 27-tel mínusz 812 osztva 4-gyel?", "brain", "41458"),
    ("Mennyi 2 a 10. hatványon?", "brain", "1024"),
    ("Mennyi négyzetgyök 81?", "brain", "9"),
    ("500 20%-a mennyi?", "brain", "100"),
    ("Mennyi 100 osztva 0-val?", "brain", "nem lehet osztani"),
    ("Hány része van a KING's RAID-nek?", "brain", "26"),
    ("Milyen műfajú a The Dawn of the Witch?", "brain", "Fantasy"),
    ("Van magyar felirata a The Kingdoms of Ruin-nak?", "brain", "magyar felirat"),
    ("Mennyi a pontszáma a The Dawn of the Witch-nek?", "brain", "6.2"),
    ("Ajánlj fantasy animét.", "brain", "fantasy"),
    ("Ajánlj horror animét.", "brain", "horror"),
    ("Milyen nap van ma?", "brain", "Ma 20"),
    ("Hány óra van most?", "brain", "Most 20"),
    ("3 km hány méter?", "brain", "3000"),
    ("20 celsius hány fahrenheit?", "brain", "68"),
    ("Szia!", "brain", "Cortex Phantom"),
]


def selftest(phantom):
    ok = 0
    failures = []
    for question, layer, needle in CASES:
        result = phantom.ask(question)
        good = result["layer"] == layer and needle.lower() in result["text"].lower()
        ok += good
        if not good:
            failures.append((question, layer, result["layer"], result["text"][:70]))
    print(f"önteszt: {ok}/{len(CASES)}")
    for f in failures:
        print("  HIBA:", f)
    return ok == len(CASES)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("question", nargs="*")
    ap.add_argument("--model", default="", help="HuggingFace modell-azonosító a saját modellhez")
    ap.add_argument("--adapter", default="", help="LoRA adapter mappa (out/phantom-core)")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    model = tokenizer = None
    if args.model or args.adapter:
        import torch
        from transformers import AutoModelForCausalLM, AutoTokenizer
        base = args.model or json.load(open(os.path.join(args.adapter, "core-meta.json")))["base"]
        tokenizer = AutoTokenizer.from_pretrained(args.adapter or base)
        model = AutoModelForCausalLM.from_pretrained(base, torch_dtype=torch.float32)
        if args.adapter:
            from peft import PeftModel
            model = PeftModel.from_pretrained(model, args.adapter)
        model.eval()

    phantom = Phantom(model=model, tokenizer=tokenizer, allow_remote=False)

    if args.selftest:
        sys.exit(0 if selftest(phantom) else 1)

    question = " ".join(args.question).strip()
    if not question:
        print(__doc__.strip())
        return
    result = phantom.ask(question)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=1))
    else:
        print(result["text"])
        print(f"\n[réteg: {result['layer']} · {result['kind']} · {result['ms']} ms]", file=sys.stderr)


if __name__ == "__main__":
    main()
