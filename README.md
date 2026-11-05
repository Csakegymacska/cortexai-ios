# Cortex AI (iOS)

A beszélgetős AI app: **Cortex Void**, az OmegaTech és a CortexAnime AI-ja.
Fekete felület, profilok, streaming válasz, kódblokkok, helyi előzmények.

- Bundle: `eu.cortex.ai` · minimum iOS **27.0** · iPhone + iPad · verzió **1.4 (5)**
- Backend: `https://cortanime.eu/api/cortexai` (Cloudflare Worker, `cortexai-api`)

## Ami benne van

| Terület | Mit tud |
|---|---|
| Chat | SSE streaming, „stop", újrapróbálás, markdown + másolható kódblokkok, időbélyegek |
| Modellek | **Cortex Phantom** (alap, hárommenetes), *Cortex Void*, *Cortex Void Deep*, *Cortex Void Fast* — beszélgetésenként váltható |
| Profilok | 4 beépített (Personal, Code, Anime, Study), saját glyph/szín/hangnem/utasítás + alapértelmezett tier |
| Könyvtár | keresés, kitűzés, törlés, átnevezés, utolsó aktivitás |
| Beállítások | alapértelmezett modell, streaming, haptika, időbélyegek, teljes törlés |
| **Memory** | a saját szavaidból kiemelt tények (név, kedvencek, tervek) minden kérésnél mennek; Beállítások → Memory: hozzáadás, törlés, kikapcsolás |
| **Cortex Void Core** | a saját, éjszakánként tanuló modell állapota: fázis, kör, pontszám a célhoz képest, identity/catalogue/hungarian mérők |
| Adat | minden a készüléken (Application Support JSON), nincs fiók, nincs tracking |

## A backend

```
GET  /api/cortexai/health   → {service:"Cortex AI", model:"Cortex Void", vendor:"OmegaTech × CortexAnime", core:true}
GET  /api/cortexai/core     → {phase, version, score, target, progress, parts, gate, selfhost, nextRound, history}
POST /api/cortexai/chat     → … + {"memory": ["A nevem Bence."]}  (az app minden kérésnél küldi)
POST /api/cortexai/chat     → {messages:[{role,content}], tier, stream}
                             SSE: data:{"meta":…} · data:{"delta":"…"} · data:[DONE]
```

A worker soha nem adja ki, milyen motor fut alatta; a kliens csak „Cortex Void"-ot vagy „Cortex Phantom"-ot lát.

**Motoriánc** (kimerülő kulcs esetén sem áll meg): saját GPU → Z.ai GLM-5.3 → Groq → Cerebras →
OpenRouter → Together → Gemini (2 modell). Csak azok az elemek élnek, amelyekhez van secret.
Egy 429/5xx után az adott motor 3 percre „padra" kerül, a következő kérés már a következő
motorral indul — a felhasználó legfeljebb annyit lát, hogy kicsit lassabb.

Üzemeltetés: `python3 tools/deploy_cortexai.py` (feltöltés + secrets + route).
Állapot: `GET /api/cortexai/engines?k=<DIAG_TOKEN>` — melyik motor él, mennyi hibával.
Korlátlan token: `cortexai-selfhost/` (saját GPU, vLLM) — lásd annak README-jét.

## Build

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project CortexAI.xcodeproj -scheme CortexAI -sdk iphoneos \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath build
```

## CI — a valódi IPA

`.github/workflows/build.yml` a `CortexAnime/cortex-ai-ios` repóban (`main` push → fut):

| lépés | mit csinál |
|---|---|
| Toolchain | `xcode-27` runner (Xcode 27.1, iOS 27.1 SDK) |
| Clamp | ha a runner SDK < 27.0, a deployment target az SDK-hoz igazodik (a build nem áll meg) |
| XcodeGen | projekt generálás |
| Unit tests | 5 teszt a szimulátoron |
| Build device app | `-sdk iphoneos`, unsigned, Release |
| Package IPA | `out/CortexAI-1.2-b3-unsigned.ipa` + sha256 |
| upload-artifact | `CortexAI-ipa` |

A futó build: `gh run watch` vagy Actions → Build. Az artifact 90 napig él.

## Kiadás

`CortexAI-1.4-b5-unsigned.ipa` — lásd `IPA-1.4-KIADAS.md` (build, sha256, telepítés).
Előző kiadások: `IPA-1.1-KIADAS.md`, `IPA-1.0-KIADAS.md` (a fájlok törölve, a leírás marad).
