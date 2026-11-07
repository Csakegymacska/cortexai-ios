# PHANTOM CORE 2 — az élő önkritika korszaka

**Dátum:** 2026-11-06 · **Mért eredmény: phantom 9,28 → 9,88 · void 9,68 → 9,90** (10 prompt × 2 pálya, xKiro-bíró)

## Mi épült (5 pillér)

### 1. Multi-jelölt + alkotmányos bíró — ÉLŐBEN (`cortexai-api/src/index.js`)
A `phantomPrepare` v2 minden hosszabb/technikai kérdésnél:
1. **két jelölt párhuzamosan** (hőmérséklet 0,4 és 0,9) — a diverzitás a lényeg;
2. **lektor-bíró** az ALKOTMÁNY (14 elv) szerint: A/B nyertes + max 4 hiba + javítási javaslat, JSON-ban;
3. **javított végleges válasz** a nyertesből, a hibákkal korrigálva.

A költségkeret (`PHANTOM.budgetMs`) lejárta után a lektor kimarad — inkább jó válasz később, mint semmi. A **`void` tier (ezt küldik az appok!) is a csővezetékre került**, nem csak a phantom csomag. Small-talk gyors úton marad. Döntés-statisztika: `GET /api/cortexai/phantom/stats`.

### 2. Szerveroldali memória (R2, felhasználónként)
`cortexai/phantom/memory/{user}.json` — a válasz után `ctx.waitUntil` kivonat max 2 stabil tényt (gyors modellel, újrapróbálással), a következő beszélgetésbe bekerül. **Eszköztől független:** ugyanaz a felhasználó másik gépről is megkapja, hogy ismerjük. Csak bejelentkezett kliensnél (`body.user`). Ellenőrzött kör: „Tibi vagy, és a Violet Evergarden rajongója." — új beszélgetésből.

### 3. Tanítókorpusz-v2 (`tools/phantom_mix.py`)
- források streamelve: **saját feliratok** (cortex-subs R2, párbeszéd-párok) + **éjjeli tanítógyár valódi RLAIF preferenciái** (R2 `cortexai/phantom/training/`);
- **FineWeb-stílusú minőségi szűrés** (`phantom_quality.score_pair`) + normalizált dedup;
- **DPO preferenciapárok:** a rejected az ALKOTMÁNY TILTOTT hibáival szennyezve (töltelék, ismétlés, angol keverés, kitérés) + a valódi lektorált preferenciák;
- a nagy fájlok **CSAK R2-ben** (`cortexai/phantom/mix/{train,val,dpo}.jsonl`), a workspace-ben csak `subs/_phantom_mix.json`;
- a tanítógyár `trainingJob` most **valódi felhasználói kérdéseket** is bányász (`readQuestions.top_unanswered`).

### 4. Kaggle notebook v2 (`cortex-phantom/kaggle/train-phantom-core-v2.ipynb`)
9 cella: GPU → csomagok (`trl` a DPO-hoz) → repó → **mix-letöltés R2-ből** → SFT (QLoRA, 1,5B) → **DPO futam** (konstíciós preferenciákon, beta 0,1) → mérés → adapter-csomagolás.

### 5. Eval-hám — mérve, minden nap
- `tools/phantom_eval.py`: 10 prompt × 2 pálya, xKiro-bíró, `--compare A B` (ez készült először);
- **éjjeli `evalJob`** a workerben: 8 prompt × bíró → R2 `cortexai/phantom/eval/{date}.json` + index; bekötve `/training/refresh`-be és a `scheduled()` cronba.

## A mérés (10 prompt, 1–10 skála)

| pálya | before | after | after2 |
|---|---|---|---|
| phantom | 9,28 | 9,35 | **9,88** |
| void | 9,68 | 9,68 | **9,90** |
| phantom min | 5,5 | 6,75 | **9,25** |

| kategória (phantom) | before | after2 | Δ |
|---|---|---|---|
| honest (ne találj ki tényt) | 5,5 | 9,75 | **+4,2** |
| knowledge (katalógus-tény) | 7,75 | 9,75 | **+2,0** |
| explain | 9,5 | 9,25 | -0,2 |
| minden más | 9,25–10 | 9,25–10 | 0 |

**A két nagy javítás konkrét oka:**
1. *honest:* a baseline kitalált egy 2037-es GDP-számot („Európai Bizottság: ~220-240 milliárd EUR… extrapolálva"); a konstíció után: „pontos előrejelzés nem létezik" + helyes elutasítás. Az 1. és 10. elv élőben dolgozik.
2. *knowledge:* a kb-réteg „hány részes"-re a kínálat-állapotot válaszolta („20 rész érhető el"); javítva: „64 részes (a katalógusban jelenleg 20 érhető el)" — `kb.js` most külön kezeli a hossz- és az elérhetőség-kérdést.

Az első „after" körben az `explain` visszaesett (a magas hőmérsékletű jelölt angolt kevert); az alkotmány 15. elve („ne keverd az angolt") + 16. elve („rossz példát ne írj") ezt javította — a megerősítő körben visszajött 9,25-re.

## Élő kötések
- worker: `cortexai-api/src/index.js` (deploy: `python3 tools/deploy_cortexai.py`) — `PHANTOM_STATS`, `evalJob`, `rememberFacts`, memória-injektálás, `void` a csővezetéken;
- `kb.js`: `EPS_Q` vs `EPS_AVAIL_Q`;
- R2: `cortexai/phantom/{memory,mix,eval,training}/`;
- éjjeli cron (cortexanime `7 4 * * *`) → `/training/refresh` → tanítógyár + eval-batteria.

## Következő lépések
1. Kaggle v2 futtatás (SFT + DPO az új mixre) — GPU-idő kérdése;
2. a növekvő `training/` + `mix/` naponta tölti az eval-trendet (`/phantom/stats`);
3. ha az eval-trend esik: az alkotmány elvei finomhangolhatók `TRAIN_PRINCIPLES`-ben (egy deploy = éles).
