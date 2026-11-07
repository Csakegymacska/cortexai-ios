# Hol lehet ingyen annyi gép, hogy ez erős legyen

Rövid válasz: **Kaggle a hely.** Heti 30 GPU-óra, kártya nélkül, T4×2 (32 GB) vagy P100 (16 GB),
12 órás futás, 20 GB kimenet. Mellé Colab (T4, ~15–30 óra/hét) és Lightning AI (havi ~22 T4-óra).
Ez együtt havonta **150–200 GPU-óra**, nulla forintért — elég ahhoz, hogy egy 1,5–3B modellt
többször újratanítsunk.

## A lehetőségek, számokkal

| hely | mit ad | mennyit | limit | kártya kell? | mire elég |
|---|---|---|---|---|---|
| **Kaggle Notebooks** | T4×2 (32 GB) vagy P100 16 GB | **30 GPU-óra/hét** | 12 óra/futás, 20 GB kimenet | nem | 1,5–3B QLoRA, naponta több kör |
| Google Colab (ingyen) | T4 16 GB | ~15–30 óra/hét (nem garantált) | 12 óra, 90 perc idle | nem | gyors kísérletek |
| Lightning AI (ingyen) | T4 / A10G | 15 kredit/hó ≈ 22 T4-óra | ~4 óra/futás | nem | IDE-s fejlesztés |
| Modal (ingyen) | H100, szerver nélküli | 30 $/hó ≈ 8 H100-óra | havonta újra | nem | nagyobb modell ritkán |
| SageMaker Studio Lab | T4 | korlátlan, 4 óra/futás | 14 nap inaktivitás után töröl | igen (fizetés nélkül) | tartalék |
| TPU Research Cloud | TPU v4–v5 | pályázat alapján, nagyon sok | angol kérelem, kutatói indoklás | nem | nulláról tanítás |
| Microsoft Founders Hub | Azure GPU kredit | pályázat, 200–150 000 $ | cégadatok, review | nem | ha egyszer cég lesz |
| NVIDIA Inception | GPU kredit | pályázat | céges regisztráció | nem | ugyanaz |

**Amit nem javaslok:** saját kártya vásárlása (nem fér bele), és bármilyen fizetős bérlés addig,
amíg az ingyenes 150 óra/hó nem fogy el.

## Mit tudunk ezen megtanítani

A T4 16 GB-jában a 4 bites (QLoRA) tanítás így fér el:

| bázis | 4 bites súly | + LoRA + gradiens | fér a T4-re? | magyar |
|---|---|---|---|---|
| **Qwen2.5-1.5B-Instruct** | ~1 GB | ~6 GB | kényelmesen | használható |
| **Qwen2.5-3B-Instruct** | ~2 GB | ~9 GB | belefér (T4×2-n lazán) | jó |
| Llama-3.2-3B-Instruct | ~2 GB | ~9 GB | belefér | jó |
| Qwen2.5-7B-Instruct | ~4,5 GB | ~14–15 GB | határeset, lassú | nagyon jó |
| GLM-4.5-Air | 106B | H100×4 kell | nem | — |

Egy kör 1200 lépés 1,5B-n T4-en: **kb. 1,5–2 óra**. Ez heti 30 órából **15 kör** — vagyis
bőven van hely iterálni: adat, arányok, hossz, minden mérhető a 60 kérdéses mérőpadon.

## A terv, hétfőtől

1. **Hét 1 — a 1,5B megtanul magyarul.** Qwen2.5-1.5B + a teljes adatunk (katalógus + 1000+
   felirat). Cél a mérőpadon: identity 100, katalógus 100, magyar 80+.
2. **Hét 2 — a 3B.** Ugyanaz az adat, nagyobb bázis. Cél: a magyar válaszok hosszabbak és
   természetesebbek, a mérőpad 90 felett.
3. **Hét 3 — a saját arculat.** A mérési hibákból generált plusz adat (ahol a modell elbukott,
   oda célzott példák), és a háromrétegű motorban a saját modell kerül a tartalék elé.
4. **Hét 4 — kiszolgálás.** GGUF export, hogy CPU-n is fusson; a worker `selfhost` eleme a saját
   modellünkre mutat. Innentől a Phantom nem függ senkitől.

## És az arena.ai?

Az Arena.ai egy összehasonlító felület: a modellek egymás ellen válaszolnak, és az emberek
szavaznak. Ahhoz, hogy a Cortex Phantom ott szerepelhessen, három dolog kell — és mind a három
megépíthető, nem pénz kérdése:

1. **Egy stabil, nyilvános végpont**, ami OpenAI-kompatibilis → ez már megvan
   (`serve_phantom.py`, `/v1/chat/completions`).
2. **Mérhető, reprodukálható eredmény** → `eval_phantom.py`, 60 fix kérdés, kategóriánkénti
   pontszám. Ezt minden körben lefuttatjuk, és közzé lehet tenni.
3. **Egy modell, ami vállalhatóan jó** → ez a 3–4 hét munkája a fenti terv szerint.

A sorrend tehát: előbb a mérés legyen hiteles (kész), aztán a modell érje el a 90 pontot,
és csak utána érdemes jelentkezni. Egy 92 pontos saját modell hitelesebb, mint egy 60 pontos,
ami csak a nevében egyedi.

## Amit ma már meg lehet csinálni egy kattintással

```
cortex-phantom/kaggle/train-phantom-core.ipynb    # Kaggle: Settings → GPU T4 x2 → Run all
cortex-phantom/train_gpu.py                       # a tanító (QLoRA, mentés, HF push, GGUF)
cortex-phantom/eval_phantom.py                     # a 60 kérdéses mérőpad
```

A jelenlegi állás a mérőpadon (agy-réteg, modell nélkül): **88,5 / 100**
(identity 100, katalógus 100, matek 100, magyar 31 — a magyar a modell dolga, azért tanulunk).
