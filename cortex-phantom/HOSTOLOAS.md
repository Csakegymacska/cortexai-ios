# CORTEX HOSTOLÁS — hol fut az AI és mennyi havonta (2026. novemberi árak)

*A felhasználó kérdése: „hol hostoljam az AI-t és mennyi lesz havonta?" —
konkrét számok, 2026-os listaárak alapján (RunPod, Vast.ai, Modal, Hetzner,
DeepSeek API).*

---

## 1. Amit ma is használunk (kb. 0 Ft-tól)

| Réteg | Hol | Havi költség |
|---|---|---|
| `cortexai-api` + `cortexanime` workerek | Cloudflare Workers | ingyenes csomagban elfér (100k kérés/nap) |
| Képek, feliratok, IPA-k | Cloudflare R2 | ~$0–2 (10 GB + kérés) |
| Képgenerálás (Cortex Void Canvas = FLUX.1-schnell) | Workers AI | 10k neuron/nap ingyen ≈ 80 kép/nap |
| Chat-motorok | Gemini ingyenes kulcs, xKiro free, Groq, Cerebras | $0 (kvótával) |
| **Összesen most** | | **≈ $0–10 / hó (~0–3 600 Ft)** |

## 2. A „selfhost" réteg — a Phantom Core (1,5B Q4) — **HOL HOSTOLD**

A modell kicsi: **4 bites, 1,5B paraméter** — GPU nélkül is fut. Három jó opció:

| Opció | Hol | Ár | Havi (folyamatos) | Mikor válaszd |
|---|---|---|---|---|
| **A. CPU VPS** ⭐ ajánlott | **Hetzner** CPX21/31 (Németország, EU) | €5,39–10,45/hó | **~6 000–12 000 Ft/hó** | a Core mindig elérhető legyen, kis forgalom |
| B. Bérelt GPU (óradíjas) | **Vast.ai** RTX 4090 | $0,29–0,34/óra | $210–245/hó nonstop — **csak napi 4-6 órára**: ~$35–60/hó | ha nagyobb modellt (20-30B) futtatnál |
| C. Serverless GPU | **RunPod Serverless / Modal T4** | $0,59–0,80/óra futás közben, 0 alvásban | valós forgalomnál **~$10–30/hó** | ha ritka, de időnként nagy a terhelés |

**A javaslat:** a Phantom Core-t **Hetzner CPU VPS-en** (A opció) — a llama.cpp
szerver tökéletesen kiszolgálja, és így a `selfhost` motor azonnal él. Ha később
kell az erősebb modell, az nem saját vas lesz, hanem API (lásd 3. pont).

### Bekötés (a worker már tudja)

A `cortexai-api` worker `selfhost` motorja három környezeti változót vár —
ezeket a `tools/deploy_cortexai.py` a `secrets/.env`-ből automatikusan felveszi:

```
SELFHOST_BASE_URL=http://<szerver-ip>:8080/v1     # llama.cpp / vLLM / Ollama
SELFHOST_API_KEY=<tetszőleges jelszó>
SELFHOST_MODEL=cortex-phantom-core
```

A szerver indítása a `cortex-phantom/serve/` mappából: `docker compose up -d`
(lásd a `serve/README.md`-t). A modell: a Kaggle-ből csomagolt LoRA adapter
ráültetve egy 1,5B-s bázisra (Q4_K_M GGUF, ~1 GB).

## 3. Ha ERŐSEBB válaszok kellenek — API, nem saját vas

A 2026-os listaárak (1 millió tokenre, USD):

| Modell | Input | Output | Megjegyzés |
|---|---|---|---|
| **DeepSeek V4.1 Flash** ⭐ | $0,15 (csúcs: $0,30) | $0,60 (csúcs: $1,20) | cache-találat: $0,003/M (!), 1M kontextus |
| DeepSeek V4 Pro | $0,66 | $1,98 | nehezebb kérdésekre |
| Groq · Llama 3.1 8B | $0,05 | $0,08 | a legolcsóbb, gyors |
| GPT-6 Luna | $0,10 | $0,50 | |
| Claude Sonnet / GPT-4o osztály | ~$2,50 | ~$10 | drága, nem kell ide |

**Mire elég $5-10 feltöltés a DeepSeeken?** ~10 000 kérés/hó (1 500 be + 400 ki
token) = **~$3–9/hó**. A DeepSeek-fiókodban jelenleg nincs egyenleg (ezért 402),
de **$5 feltöltéssel a lánc legerősebb motorja feloldódik** — ez a legjobb
ár/érték erősítés jelenleg.

## 4. A javasolt teljes csomag

| Sor | Mi | Havi |
|---|---|---|
| 1 | Cloudflare (Workers + R2 + Workers AI) | ~$0–10 |
| 2 | Hetzner CPU VPS (Phantom Core selfhost) | ~$6–12 (≈ 6 000 Ft) |
| 3 | DeepSeek API feltöltés (V4.1 Flash) | ~$5–10 forgalomtól |
| **Összesen** | | **~$10–30 / hó (≈ 4 000–11 000 Ft)** |

Ez a teljes Cortex-rendszer: web, app, chat, képgenerálás, fordítás, saját modell.

*Frissítve: 2026-11-06 · források: RunPod/Vast.ai/Modal listaárak (2026 Q4),
DeepSeek hivatalos árlista (2026-10), Hetzner.*
