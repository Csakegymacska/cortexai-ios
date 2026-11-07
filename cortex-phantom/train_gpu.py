#!/usr/bin/env python3
"""Cortex Phantom — GPU-s tanulókör (Kaggle / Colab).

A CPU-s napi kör (cortex-void-core) a folytonosságot adja: minden éjjel tanul egy kicsit.
Ez a szkript a nagy lépés: 4 bites QLoRA egy 1,5–3 milliárd paraméteres bázison, egy
ingyenes T4-en vagy T4×2-n, kb. 1–3 óra alatt.

  # száraz próba (bármilyen gépen, GPU nélkül)
  python3 train_gpu.py --dry

  # élesben (Kaggle T4×2, 12 órás limit alatt kényelmesen)
  python3 train_gpu.py --data data --base Qwen/Qwen2.5-1.5B-Instruct \
      --steps 1200 --out /kaggle/working/phantom --push-to HF_USER/cortex-phantom-core

Amit ad:
  out/adapter/           a LoRA (néhány 10 MB) — ezt tölti fel minden mentésnél
  out/merged/            4 bites → fp16 összefésült modell (opcionális, nagy)
  out/phantom.gguf       llama.cpp formátum, hogy bárhol fusson (opcionális)
  out/report.json        loss + mérési eredmény

Miért QLoRA és miért 1,5–3B: a T4 16 GB-jába egy 4 bites 3B modell + LoRA + gradiens
kényelmesen belefér; a 8B már csak trükkökkel. A 3B magyarul már használható, az 1,5B gyors.
"""
import argparse, json, os, sys, time

SYSTEM = ("Te a Cortex Phantom vagy: az OmegaTech és a CortexAnime AI-ja. "
          "Válaszolj magyarul, tömören, konkrétan. Soha ne nevezz meg más modellt vagy labort.")

DEFAULT_BASE = "Qwen/Qwen2.5-1.5B-Instruct"


def load_jsonl(path):
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def build_examples(rows):
    """[{messages:[…]}] → [{'text': …}] a chat-sablonhoz."""
    out = []
    for row in rows:
        msgs = row.get("messages") or []
        if not any(m.get("role") == "assistant" for m in msgs):
            continue
        out.append({"messages": msgs})
    return out


def plan(args):
    train_path = os.path.join(args.data, "train.jsonl")
    val_path = os.path.join(args.data, "val.jsonl")
    train = load_jsonl(train_path) if os.path.exists(train_path) else []
    val = load_jsonl(val_path) if os.path.exists(val_path) else []
    print(json.dumps({
        "base": args.base,
        "train": len(train),
        "val": len(val),
        "steps": args.steps,
        "batch": f"{args.batch} x {args.accumulate} (effektív {args.batch * args.accumulate})",
        "seq": args.max_len,
        "lora": f"r={args.lora_r} alpha={args.lora_alpha}",
        "quant": "4-bit nf4" if not args.no_quant else "fp16",
        "out": args.out,
    }, ensure_ascii=False, indent=1))
    if not train:
        print("nincs tanítóadat: futtasd a collect.py + build_dataset.py párost", file=sys.stderr)
    return train, val


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="data")
    ap.add_argument("--out", default="out/phantom")
    ap.add_argument("--base", default=DEFAULT_BASE)
    ap.add_argument("--steps", type=int, default=1200)
    ap.add_argument("--batch", type=int, default=2)
    ap.add_argument("--accumulate", type=int, default=8)
    ap.add_argument("--lr", type=float, default=2e-4)
    ap.add_argument("--max-len", type=int, default=1024)
    ap.add_argument("--lora-r", type=int, default=16)
    ap.add_argument("--lora-alpha", type=int, default=32)
    ap.add_argument("--save-every", type=int, default=200)
    ap.add_argument("--no-quant", action="store_true")
    ap.add_argument("--merge", action="store_true")
    ap.add_argument("--gguf", action="store_true")
    ap.add_argument("--push-to", default="", help="HuggingFace repo, pl. felhasznalo/cortex-phantom-core")
    ap.add_argument("--report-url", default="https://cortanime.eu/api/cortexai")
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()

    train, val = plan(args)
    if args.dry:
        sample = build_examples(train[:1])
        print("\npélda, ahogy a modell látja:")
        if sample:
            for m in sample[0]["messages"]:
                print(f"  [{m['role']}] {m['content'][:110]}")
        else:
            print("  (nincs adat — ez csak a konfiguráció ellenőrzése)")
        return 0
    if not train:
        return 2

    os.makedirs(args.out, exist_ok=True)
    import torch
    from datasets import Dataset
    from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training
    from transformers import (AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig,
                              Trainer, TrainingArguments)

    print("GPU:", torch.cuda.get_device_name(0) if torch.cuda.is_available() else "nincs — CPU-ra esik vissza")
    dtype = torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16

    quant = None
    if not args.no_quant:
        quant = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_compute_dtype=dtype,
            bnb_4bit_use_double_quant=True,
        )

    tokenizer = AutoTokenizer.from_pretrained(args.base, trust_remote_code=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    model = AutoModelForCausalLM.from_pretrained(
        args.base, quantization_config=quant, torch_dtype=dtype,
        device_map="auto", trust_remote_code=True,
    )
    model = prepare_model_for_kbit_training(model)
    model = get_peft_model(model, LoraConfig(
        task_type="CAUSAL_LM", r=args.lora_r, lora_alpha=args.lora_alpha,
        lora_dropout=0.05, bias="none",
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                        "gate_proj", "up_proj", "down_proj"],
    ))
    model.print_trainable_parameters()

    def encode(row):
        # Csak a válaszon tanulunk (a rendszer+felhasználó tokenjei -100): kis adaton ez a
        # különbség mérhető, a modell nem a kérdést próbálja megjósolni.
        msgs = row["messages"]
        prefix = tokenizer.apply_chat_template(msgs[:-1], tokenize=False, add_generation_prompt=True)
        full = tokenizer.apply_chat_template(msgs, tokenize=False, add_generation_prompt=False)
        p_ids = tokenizer(prefix, add_special_tokens=False)["input_ids"]
        f_ids = list(tokenizer(full, truncation=True, max_length=args.max_len,
                               add_special_tokens=False)["input_ids"])
        cut = min(len(p_ids), len(f_ids))
        labels = [-100] * cut + f_ids[cut:]
        return {"input_ids": f_ids, "attention_mask": [1] * len(f_ids), "labels": labels}

    train_ds = Dataset.from_list(build_examples(train)).map(encode, remove_columns=["messages"])
    val_ds = Dataset.from_list(build_examples(val)).map(encode, remove_columns=["messages"]) if val else None

    class PadCollator:
        """Kézi padding — a beépített collator a labels oszlopon elhasal."""
        def __init__(self, pad_id):
            self.pad_id = pad_id

        def __call__(self, features):
            width = max(len(f["input_ids"]) for f in features)
            out = {"input_ids": [], "attention_mask": [], "labels": []}
            for f in features:
                pad = width - len(f["input_ids"])
                out["input_ids"].append(list(f["input_ids"]) + [self.pad_id] * pad)
                out["attention_mask"].append(list(f["attention_mask"]) + [0] * pad)
                out["labels"].append(list(f["labels"]) + [-100] * pad)
            return {k: torch.tensor(v, dtype=torch.long) for k, v in out.items()}

    training = TrainingArguments(
        output_dir=os.path.join(args.out, "checkpoints"),
        max_steps=args.steps,
        per_device_train_batch_size=args.batch,
        gradient_accumulation_steps=args.accumulate,
        learning_rate=args.lr,
        lr_scheduler_type="cosine",
        warmup_ratio=0.03,
        logging_steps=10,
        save_steps=args.save_every,
        save_total_limit=2,
        gradient_checkpointing=True,
        bf16=(dtype == torch.bfloat16),
        fp16=(dtype == torch.float16),
        report_to=[],
        dataloader_num_workers=2,
        remove_unused_columns=False,
        optim="paged_adamw_8bit" if not args.no_quant else "adamw_torch",
    )

    trainer = Trainer(model=model, args=training, train_dataset=train_ds, eval_dataset=val_ds,
                      data_collator=PadCollator(tokenizer.pad_token_id))
    started = time.time()
    trainer.train()
    minutes = round((time.time() - started) / 60, 1)

    adapter_dir = os.path.join(args.out, "adapter")
    model.save_pretrained(adapter_dir)
    tokenizer.save_pretrained(adapter_dir)

    losses = [row["loss"] for row in trainer.state.log_history if "loss" in row]
    report = {
        "base": args.base,
        "steps": args.steps,
        "minutes": minutes,
        "train_rows": len(train),
        "first_loss": round(losses[0], 4) if losses else None,
        "last_loss": round(losses[-1], 4) if losses else None,
        "adapter": adapter_dir,
    }

    if args.push_to:
        try:
            from huggingface_hub import HfApi
            api = HfApi()
            api.create_repo(args.push_to, exist_ok=True, private=False)
            api.upload_folder(folder_path=adapter_dir, repo_id=args.push_to,
                              commit_message=f"phantom core: {args.steps} steps on {args.base}")
            report["pushed"] = args.push_to
        except Exception as exc:
            report["push_error"] = str(exc)[:200]

    if args.merge:
        try:
            merged_dir = os.path.join(args.out, "merged")
            merged = model.merge_and_unload()
            merged.save_pretrained(merged_dir, safe_serialization=True)
            tokenizer.save_pretrained(merged_dir)
            report["merged"] = merged_dir
        except Exception as exc:
            report["merge_error"] = str(exc)[:200]

    if args.gguf:
        try:
            import subprocess
            gguf = os.path.join(args.out, "phantom.gguf")
            subprocess.run([sys.executable, "-m", "pip", "install", "-q", "llama-cpp-python"], check=False)
            subprocess.run(["python", "-m", "llama_cpp.convert",
                            os.path.join(args.out, "merged"), "--outfile", gguf, "--outtype", "q4_k_m"],
                           check=True)
            report["gguf"] = gguf
        except Exception as exc:
            report["gguf_error"] = str(exc)[:200]

    json.dump(report, open(os.path.join(args.out, "report.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(json.dumps(report, ensure_ascii=False, indent=1))

    # A kör eredménye megy a workernek, hogy az app Cortex Void Core panelje lássa.
    token = os.environ.get("CORE_TOKEN", "")
    if token and args.report_url:
        try:
            import urllib.request
            payload = json.dumps({"score": 0, "parts": {}, "version": 0,
                                  "trained_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}).encode()
            req = urllib.request.Request(args.report_url.rstrip("/") + "/core/report", data=payload, method="POST")
            req.add_header("Content-Type", "application/json")
            req.add_header("X-Core-Token", token)
            with urllib.request.urlopen(req, timeout=30) as resp:
                print("worker:", resp.read()[:200])
        except Exception as exc:
            print("a worker nem fogadta el:", exc)
    return 0


if __name__ == "__main__":
    sys.exit(main())
