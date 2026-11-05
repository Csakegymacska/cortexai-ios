# Cortex AI 1.1 — Cortex Void Canvas

**Fájl:** `cortexai-ios/build/CortexAI-1.1-b2-unsigned.ipa` · 4 230 289 B
**sha256:** `16e1c2d157d9afa1cc6b6940b9fe226af86e38b9142e5544d8ba7ecf77905b49`

| | |
|---|---|
| App | Cortex AI 1.1 (build 2) |
| Bundle ID | `eu.cortex.ai` |
| Minimális iOS | 27.0 · iPhone + iPad · arm64 |
| Építő | Xcode 27.1, iOS 27.1 SDK, Release, unsigned |
| CI futás | `41234889092` — 9/9 lépés zöld |

## Új ebben a verzióban

**Cortex Void Canvas** — képstúdió a chat mellett (a fejléc `wand.and.stars` gombja):

- prompt mező + 6 stílus: Auto, Anime, Mozi, Ikon, 3D, Vázlat
- a munka aszinkron: a backend elindítja a jobot, az app 2,5 s-onként kérdez rá,
  közben „Festés… 12 s" számláló, stop gombbal megszakítható
- kész kép: nagy előnézet, **Megosztás** (rendszer share sheet) és **Link** másolás
- az adott körben készült képek csíkja alul, egy koppintással visszahozható
- a stúdió minden felirata magyar, a márka „Cortex Void Canvas"

**Backend oldal** (`cortexai-api`):

| végpont | mit csinál |
|---|---|
| `POST /api/cortexai/image` | `{prompt, style}` → `{id, status}` (xKiro job indítás) |
| `GET /api/cortexai/image/{id}` | `{status, url}` — a CDN link, ha kész |
| `/health` | új `image: true` mező |

Az öt chat-lépcső változatlan (qwen3.8-max → qwen3.7-max → mistral-large →
command-a-plus → qwen3.5-flash), a képmodell ingyenes, tehát a képstúdió sem kerül pénzbe.
A képstúdiónak külön rate limitje van: 30 kép/óra kliensenként, 60/IP.

## Telepítés

Aláíratlan IPA — Sideloadly / AltStore / Esign aláírja a saját tanúsítványoddal,
vagy TrollStore aláírás nélkül. iOS 27.0+ kell.

## Ha valami elakad

- „The image studio is busy" → a képmodell éppen telített, 10–20 s múlva újra.
- „This one is taking too long" → 90 × 2,5 s után az app feladja; ilyenkor a job
  a háttérben még elkészülhet, de az app már nem várja meg.
