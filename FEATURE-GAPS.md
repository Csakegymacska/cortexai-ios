# Mi van a többi AI appban, ami nekünk még nincs — 2026.11. kutatás

Források: frankx.ai (ChatGPT/Claude/Gemini összehasonlítás), hackceleration,
tech-insider, viralmarketinglab (2026-os körképek), builderai/simplismart/perplexity
magazine (open képgenerátor-modellek).

## A mezőny 2026-ban

| Képesség | ChatGPT | Claude | Gemini | **Cortex AI** |
|---|---|---|---|---|
| Képgenerálás | GPT Image 2 | — (nincs) | Nano Banana Pro | **tervben (Void Canvas)** |
| Élő hang (megszakítható) | Advanced Voice | Voice (mobil) | Gemini Live | ✗ (csak diktálás + felolvasás) |
| Memória beszélgetések között | igen | igen (projektek) | igen (fiókhoz) | részleges |
| Canvas / dokumentum | igen | Artifacts | Canvas | ✗ (export van) |
| Projektek | igen | igen (5 ingyen) | — | ✗ („Projektek" lap van, könnyű súlyú) |
| Ütemezett / proaktív feladatok | igen | — | — | ✗ |
| Deep research + források | igen | Research | Deep Research | ✗ (kutatás-mód forrásjelzés nélkül) |
| Egyedi asszisztensek | custom GPT-k | — | Gems | részleges (mentett utasítások) |

## Következő lépések (sorrendben)

1. **Képgenerálás — a legnagyobb rés.** A „Cortex Void Canvas" az appban már
   hívja a `POST /image`-t; a motor a **Cortex Phantom**ba épül be
   (lásd `cortex-phantom/imagegen.py`).
2. **Forrásjelzés a kutatás-módban** — minden válasz alá URL-lista (Perplexity-szint).
3. **Élő hang** — a SpeechEngine + Dictation összekötése egy megszakítható
   hang-beszélgetéssé.
4. **Memória-kezelő** — átlátható lista + törlés (adatvédelmi elvárás).
5. **Ütemezett feladatok** — reggeli összefoglaló, árfigyelés stb.

## Képgenerátor-modell-választás (HuggingFace, 2026.11)

| Modell | Méret | Licenc | VRAM | Mikor |
|---|---|---|---|---|
| **Qwen-Image (2512)** | 20B | Apache 2.0 | 16 GB FP8 / 8 GB GGUF | legjobb open minőség + szövegrajzolás |
| **Z-Image Turbo** | 6B | Apache 2.0 | 16 GB (kisebbel is) | gyors, napi használat |
| **FLUX.2 [klein]** | 4B | Apache 2.0 | ~13 GB | valós idejű |
| **FLUX.2 [dev]** | 32B | nem kereskedelmi | 24–32 GB | csúcsminőség, ha szabad |
| Illustrious XL | SDXL-alap | Fair AI | 6–8 GB | **anime/karakter** (CortexAnime!) |

Döntés a Phantomhoz: **elsődleges Qwen-Image, gyors fallback Z-Image Turbo,
anime-mód Illustrious XL** — mind Apache 2.0 / nyílt, Kaggle T4 (16 GB) futtatja.
