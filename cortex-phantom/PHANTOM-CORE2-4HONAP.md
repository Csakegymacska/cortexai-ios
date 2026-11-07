# PHANTOM CORE 2 — 4 hónapos haditerv (2026-11-07 → 2026-03-07)

**Cél:** a Phantom Core elérje a „nagy modell" szerepet — hogy ne támaszkodjunk másra.
Napi 5–6 óra tanítás, Kaggle GPU. Ez a terv reális célokkal és mérhető kapukkal.

---

## 0. Őszinte alapvetés (ez dönti el a 4 hónap sikerét)

Egy 1,5B / 8B modell **soha nem lesz általános értelemben Grok 4.20** — és nem is az kell.
A győzelem így néz ki:

> **Phantom Core + a saját rendszerünk = a MI feladatainkon jobb, mint a nagy modellek.**

Miben vagyunk mi jobbak bárkinél: a Cortex-személyiség, a magyar folyékonyság, az
agent/eszközkezelés, a katalógus-tudás, a becsületes stílus. **Ebben kell verhetetlennek
lenni** — ezt méri a napi eval, ez dönt a váltásról.

A függés megszűnése két lépcső:
1. **Desztilláció** — a nagy modellek (Grok) MESTERKÉNT termelik az adatot a kicsinek
   (`tools/phantom_distill.py`), napi szinten. Ezzel a tudás átköltözik.
2. **Váltás** — amikor a saját modell hozza a számot, a `selfhost` engine az élre kerül,
   a Grok pedig visszalép tartaléknak. A lánc erre már kész.

---

## 1. Bázis-döntés (a legfontosabb technikai lépés)

| | most | 2. hónaptól |
|---|---|---|
| bázis | Qwen2.5-1.5B-Instruct | **Qwen3-8B / Llama-3.1-8B osztály** |
| módszer | QLoRA (4-bit) | QLoRA (4-bit) + később teljes finomhangolás a 8B-ra |
| Kaggle | T4×2 — kényelmes | T4×2 — 8B QLoRA belefér (16 GB + gradient checkpointing) |

- **1. hónap:** 1.5B → 3B (biztonságos ugrás, a notebook már tudja)
- **2. hónap:** 3B → 8B (ez a végleges formátum a 4 hónapra)
- A 14B+ **nem** fér a Kaggle kvótájába reálisan — 8B + jó adat + desztilláció veri a 14B-t gyengébb adattal.

## 2. Kaggle-napirend (5–6 óra / nap)

A Kaggle heti GPU-kerete **30 óra** — ez heti 5 nap × 6 óra (vagy 6 nap × 5 óra). Betartva:

| blokk | idő | mit csinál |
|---|---|---|
| 1. futam | 2,5–3 óra | SFT / DPO lépés az aznapi mix-sel (checkpoint-mentéssel) |
| 2. futam | 1,5–2 óra | eval a checkpointon (saját eval-készlet, helyben) |
| 3. blokk | 1 óra | adapter-csomagolás + feltöltés R2-re (`cortexai/phantom/checkpoints/`) |
| ráhagyás | 0,5 óra | hibakeresés, visszatöltés (resume) — a Kaggle-munkamenet újraindul, ezért MINDIG checkpoint |

**Aranyszabály:** minden futam végén checkpoint R2-re — a Kaggle munkamenet nem él túl.

## 3. Fázisok (hónap = 4 hét)

### Hónap 1 — Alap + magyar folyékonyság
- **Adat:** desztilláció napi 50–100 mester-pár + felirat-korpusz (2M+ sor, HU-EN) + kód
- **Tanítás:** folyamatos előtanítás-szerű SFT a magyar/domain anyagon, majd SFT v1
- **Kapu (hó végén):** magyar folyékonyság emberi mintán 4/5; persona-követés 9/10 a saját evalon
### Hónap 2 — Utasítás-követés + DPO v1
- **Tanítás:** multi-task SFT (chat, összefoglaló, kód, agent-terv) + DPO az éjjeli preferenciákon
- **Adat:** desztilláció napi 150–250 pár (a tanítógyár már megy, csak skálázni kell)
- **Kapu:** `phantom_eval --compare selfhost phantom-stack` — önállóan **9,0 felett** átlagban
### Hónap 3 — Agent + eszközök
- **Tanítás:** valódi runner-nyomokon (a te futtatásaid: terv → bash → kimenet → válasz) + DPO v2
- **Adat:** az app beszélgetései + a lektorált preferenciák; desztilláció napi 300+ párra
- **Kapu:** agent-feladatok sikeressége 80%+ a saját mérőállomáson (eszközhívás, terv, végrehajtás)
### Hónap 4 — Fényezés + a váltás
- **Tanítás:** finom DPO (emberi ízlés-körök is — te pontozol napi 10-et), hosszú-kontextus SFT
- **A VÁLTÁS feltétele (mindegyik kell):**
  1. `phantom_eval`: önálló átlag **≥ 9,5**, egyik kategória sem **8,5 alatt**
  2. magyar folyékonyság: 5/5 emberi mintán
  3. agent-sikeresség **≥ 85%**
  4. válaszidő p95 **< 8 mp** (saját kiszolgálás)
  5. **1 hét árnyék-üzem** hiba nélkül
- **A váltás:** a `selfhost` engine a `phantom` lánc élére; Grok tartalék 2. helyre; bármilyen
  esésnél automatikus visszaesés — a felhasználó sosem marad agy nélkül.

## 4. Mi dolgozik MAJD IS melletted (automatika, éjjel)

- **`tools/phantom_distill.py`** — mester-adat gyár (Grok tanítja a kicsit), R2-re
- **`tools/phantom_mix.py`** — minőségi szűrés + DPO-párok + mix-építés (már megy)
- **`tools/phantom_eval.py` + éjjeli evalJob** — napi mérés, trend R2-re (már megy)
- **checkpoint-kör** — te csak indítod a Kaggle-ban a nap futamát

## 5. Kockázatok őszintén

| kockázat | kezelés |
|---|---|
| Kaggle-kvóta (30 h/ét) kevesebb mint a napi 5–6 óra | heti 5 nap × 6 óra; a desztilláció és eval szerveren fut |
| a 8B-s QLoRA lassú T4-en | éjszakai futam + checkpoint-resume; 3B-n tanuljuk ki a hibákat |
| „jó lesz-e valaha?" | a havi kapuk megmondják — ha a 2. hó végi 9,0 nincs meg, bázist/stratégiát váltunk, nem várjuk a 4. hónapot |
| a desztillált adat túl „Grok-ízű" | az identitás-szűrések + a saját lektor preferenciái felülírják a stílust |

---

**A mai állapot:** a tanítógyár, az eval és a notebook megvan; a hiányzó láncszem
a **mester-adat** (`phantom_distill.py`) és a **bázis-ugrás** (1.5B → 8B). Ezekkel
indul a 4 hónap.
