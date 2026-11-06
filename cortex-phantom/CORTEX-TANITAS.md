# CORTEX TANÍTÁS — a nyilvános receptek magyar adaptációja

*A felhasználó kérése (2026-11-06): „erősíteni kell, mert gyenge — olvasd el,
hogyan tanították a Claude-ot, az nyilvános, és használd fel módszerként." Ez
a dokumentum pontosan ezt teszi: összefoglalja a két legfontosabb nyilvános
módszert, és leírja, hogyan ültettük át a Cortex tanítási láncába.*

---

## 1. Amit a nyilvános kutatásból átvettünk

### A) Anthropic: Constitutional AI + karakter-tréning (Claude)

Források: *Constitutional AI: Harmlessness from AI Feedback* (Anthropic, 2022) ·
*Claude's character* (Anthropic Research, 2024).

| Lépés | A nyilvános módszer | A Cortex-ben |
|---|---|---|
| **Konstíció** | Olvasható, explicit elvek dokumentuma (nem fekete doboz emberi címkék) | `cortex-phantom/CORTEX-KONSTICIO.md` — 32 elv, 7 fejezet (igazmondás, segítőkészség, magyar nyelv, felirat-minőség, tömörség, ártalmatlanság, karakter) |
| **SL-CAI (felügyelt)** | Modell válaszol → önmagát kritizálja egy elv alapján → átírja → SFT a „javított" párokon | `tools/phantom_constitution.py --mode revise` — a korpusz párjaira futtat kritika+javítás kört |
| **RLAIF (preferencia)** | Két válasz ugyanarra a promptra → a modell az elv alapján megrendezzi → preferencia-modell / DPO | `tools/phantom_constitution.py --mode synth` — `prefs.jsonl` (prompt/chosen/rejected/principle) |
| **Karakter-tréning** | Trait-lista → szintetikus üzenetek → a modell saját válaszait rangsorolja → preferencia-adat | A konstíció G. fejezete (kíváncsiság, nyitottság, alaposság, tömörség, őszinteség) + a seed-promptok |
| **Véletlen elv-mintavétel** | Az elveket random húzzák, hogy a modell ne egyetlen elvre lőjön túl | `random.choice(principles)` minden párnál |

**A kulcs-tanulság:** az AI tanulhat a saját, elvek alapján adott értékeléséből —
az emberi címkézés drága és nem skálázódik, az elvek olvashatók és
megkérdőjelezhetők.

### B) Hugging Face: FineWeb adat-recept

Forrás: *The FineWeb Datasets: Decanting the Web for the Finest Text Data at
Scale* (HF, 2024) · `HuggingFaceFW/fineweb` dataset card.

| Lépés | A nyilvános módszer | A Cortex-ben |
|---|---|---|
| **Heurisztikus minőségi szűrés** | Gopher-ismétlés, C4-sorvégi írásjel, listaszerű/rosszul formázott szöveg kiszórása | `tools/phantom_quality.py` — ismétlési arány, sorvégi írásjel, placeholder-hulladék, szóhurok, futószöveg |
| **Felirat-specifikus jelek** | (a FineWeb-2 nyelv-specifikus jelei nyomán) | angolban ragadt sorok aránya, cue-hossz, 44 karakteres törés |
| **LLM-pontozás → szűrő** | FineWeb-Edu: LLM 0–5 pontoz mintákat → kalibrált küszöbök | `--llm-calibrate N` — Gemini pontoz, a heurisztika-küszöb igazodik (korreláció-riport) |
| **Dedup** | MinHash 5-gram, snapshotonként (kiderült: jobb, mint a globális) | a `phantom_corpus.py` dedupe lépése + a revíziós körökben `base != revised` szűrő |
| **Abláció** | Minden döntést kis modellel visszaigazolnak | a `report.json` + a `llm_calibration` mezők; a Kaggle mérőpad (7. cella) a változásokat méri |

**A kulcs-tanulság:** az adatminőség többet számít, mint az adatmennyiség —
a FineWeb-Edu kevesebb tokenből jobb MMLU-t ért el, mint a nagyobb, szűretlen
készletek.

---

## 2. A Cortex tanítási lánc (gyakorlat)

```
források (sarpba 91k · saját felirat 600k · alpaca-hu 15k · katalógus-QA 1,2k)
   │
   ├─ phantom_quality.py   → fineweb-stílusú szűrés → train-q.jsonl
   │
   ├─ phantom_constitution.py --mode synth   → sl-cai.jsonl + prefs.jsonl
   │       (konstíció: CORTEX-KONSTICIO.md · motor: Gemini)
   │
   └─ train-mix.jsonl (train-q + sl-cai) → Kaggle QLoRA (train-phantom-core.ipynb)
                                                    │
                                        prefs.jsonl → DPO-futam (terv)
```

- **Napi kör:** a worker „Cortex Void Core" hurokja a mérőpadon csak akkor
  léptet elő egy LoRA-t, ha veri a bajnokot — ez a FineWeb-féle „csak
  bizonyított változás" elv.
- **Mérés:** ugyanaz a mérőpad minden körben (lásd a notebook 7. celláját).

## 3. Mit nem csinálunk (és miért)

- **Nem distillálunk nagy modell-kimeneteket** (pl. Claude/Haiku kimenetét
  átvenni tanítóadatnak) — korábban elutasítva: a nagy modell stílusát másolnánk,
  nem a sajátunkat tanulnánk. A konstíciós önkritika ezzel szemben a *saját*
  válaszainkat javítja.
- **Nem másoljuk a Claude konstícióját szó szerint** — a módszert vettük át, az
  elvek a saját termékünkre (magyar nyelv, felirat-minőség, anime-közönség)
  vannak szabva.

## 4. Források

1. Anthropic — *Constitutional AI: Harmlessness from AI Feedback* (2022)
2. Anthropic Research — *Claude's character* (2024) — anthropic.com/research/claude-character
3. Hugging Face — *The FineWeb Datasets* (2024) — arXiv:2406.17557 · huggingface.co/datasets/HuggingFaceFW/fineweb
4. A saját korpusz dokumentációja: `cortex-phantom/data/CORPUS.md`

*Verzió: 1.0 · 2026-11-06*
