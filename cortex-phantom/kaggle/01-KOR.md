# 1. KÖR — az első 5–6 órás tanítás (Kaggle, T4×2)

Kész állapot: a repóban a tanítóscriptek, az R2-en a friss korpusz
(238 train · 26 val · 119 DPO — benne 25 mai mester-pár). Neked csak
gombokat kell nyomni.

---

## 0. Kaggle előkészítés (5 perc)

1. **kaggle.com → Code → New Notebook**
2. **Settings** (jobb oldali panel):
   - *Accelerator* → **GPU T4 ×2**
   - *Session length* → **12 óra** (a maximum)
   - *Internet* → **ON** (a csomagok + HF letöltés kell)
3. **Secrets** (a Settings alatt, kulcs ikon) — add hozzá ezt a hármat
   (a notebook innen olvassa a mix letöltéséhez):
   - `CLOUDFLARE_EMAIL`
   - `CLOUDFLARE_API_KEY`
   - `CF_ACCOUNT_ID`
   (az értékeik a te `secrets/.env`-fájlodban vannak — ugyanazok)

## 1. Notebook betöltése (1 perc)

**File → Import notebook → GitHub** és be:

    https://github.com/Csakegymacska/cortexai-ios/blob/main/cortex-phantom/kaggle/train-phantom-core-v2.ipynb

(Ezért raktam fel ma a repóba — eddig hiányzott volna a tanítóscript.)

## 2. Futtatás — a 9 cella SORRENDBEN (Run all is mehet)

| cella | mit csinál | idő | mit nézz |
|---|---|---|---|
| 1 | GPU ellenőrzés | 1 mp | „Tesla T4 ×2" — ha nincs GPU, állj meg |
| 2 | csomagok (unsloth, trl…) | 2–3 perc | hiba nélkül lefusson |
| 3 | repó klónozás | 1 perc | megjelenik a `cortex-phantom` mappa |
| 4 | **korpusz letöltés R2-ről** | 1 perc | „train/val/dpo" sorok száma |
| 5 | **SFT — QLoRA, 1500 lépés** | **~2–2,5 óra** | a **loss** menjen 1,2 alá; ha 2,5 felett áll meg, kevés a lépés |
| 6 | **DPO — preferenciák** | **~1–1,5 óra** | a reward-margó nőjön |
| 7 | helyi mérés | 5–10 perc | kimaradhat, ha nincs XKIRO-titok |
| 8 | csomagolás | 1 perc | `final/` adapter — ez az eredmény |

**Összesen: ~4–5 óra** — belefér az 5–6 órás körbe.

## 3. Checkpoint-fegyelem (aranyszabály)

- Kaggle-nél a `/kaggle/working` **Session végén törlődik**, az **Output** marad meg.
- A 8. cella után a `phantom-dpo/final` adapter megjelenik **Output**ként —
  az *mentve van*. Ha a session idő előtt meghal, a cellát újra kell futtatni
  (az SFT-től nem — az a 6. cellában van, ha addig eljutottál, a DPO újraindul).
- Ha látod, hogy kevés az idő: a **6. cella (DPO) után azonnal futtasd a 8-at** —
  az adapter a lényeg, a mérés ráér.

## 4. Az eredmény — mi történik utána

1. A `final/` adapter letöltése az Output-ból (pár 10 MB)
2. **Töltsd fel nekem** (bedobod a chatbe, vagy a Kaggle Output linket küldöd)
3. Én betöltöm a szerverre, és **lefuttatom rajta a teljes mérőpadot** —
   megmondjuk, hol tart a Phantom Core az első kör után (a 4 hónapos terv 1. kapuja felé)

## 5. Ha valami elromlik

| hiba | megoldás |
|---|---|
| „No GPU" | Settings → Accelerator → T4×2; ha nincs szabad GPU, mentsd a notebookot, később indítsd (a heti keret 30 óra) |
| cella 4: titok-hiba | a Kaggle Secrets nevei pontosan: `CLOUDFLARE_EMAIL`, `CLOUDFLARE_API_KEY`, `CF_ACCOUNT_ID` |
| cella 5: CUDA OOM | a `STEPS`-et ne, a `BASE`-t ne most piszkáld — jelentsd, és a 3B-s notebookot adom |
| bármi más | screenshot ide, és megmondom |
