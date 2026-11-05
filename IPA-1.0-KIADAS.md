# Cortex AI 1.0 — első IPA

**Fájl:** `cortexai-ios/build/CortexAI-1.0-unsigned.ipa` · 4 152 485 B
**sha256:** `948048ae9ebd1f19e1f17cf459637c116bdffa6ecb671ce574b26976d4fa46a9`

| | |
|---|---|
| App | Cortex AI 1.0 (build 1) |
| Bundle ID | `eu.cortex.ai` |
| Minimális iOS | **27.0** |
| Eszköz | iPhone + iPad (univerzális, arm64) |
| Építő | Xcode 27.1, iOS 27.1 SDK (`iphoneos27.1`), Release |
| Aláírás | **nincs** (unsigned — a telepítő tool írja alá) |
| CI futás | [`41232964674`](https://github.com/CortexAnime/cortex-ai-ios/actions/runs/41232964674) — mind a 9 lépés zöld |

## Mi van benne

- Chat streaminggel (SSE), stop / újrapróbálás, markdown, másolható kódblokkok, időbélyegek
- Három Cortex Void szint: *Void*, *Void Deep*, *Void Fast* — beszélgetésenként váltható
- Profilok: 4 beépített (Personal, Code, Anime, Study) + saját profil (glyph, szín, hangnem, utasítás)
- Könyvtár: keresés, kitűzés, átnevezés, törlés
- Beállítások: alapértelmezett szint, streaming, haptika, időbélyegek, teljes törlés
- Minden adat a készüléken (Application Support JSON), nincs fiók, nincs tracking
- Fekete felület, saját app ikon (1024, Asset Catalog), Privacy Manifest

## A backend, ami alatta van

Az app a `https://cortanime.eu/api/cortexai` workert hívja. 2026-10-31 este a worker átállt az
**xKiro** útvonalra: 5 lépcsős ingyenes modell-lánc (`qwen3.8-max` → `qwen3.7-max` →
`mistral-large` → `command-a-plus` → `qwen3.5-flash`), utána a régi tartalék motorok.
Egy 429/5xx után az adott lépcső 3 percre kiesik, a kérés a következővel megy tovább.

Élő ellenőrzés (deploy után):
`/health` → ok, `redundancy: 8` · nem-stream válasz 4,2 s · stream 0,9 s / 7 delta ·
identitás-próba: „Cortex Void, az OmegaTech és a CortexAnime AI-ja."

Az app és a worker soha nem nevezi meg a valódi modellt — a válasz mindig Cortex Void.

## Telepítés

Az IPA **aláíratlan**, ezért közvetlenül nem megy fel a készülékre. Három út:

1. **Sideloadly / AltStore / Esign** — húzd rá az IPA-t, add meg a saját Apple ID-t vagy a
   meglévő tanúsítványodat; a tool aláírja és felteszi.
2. **Saját fejlesztői tanúsítvány** — `codesign -f -s "Apple Development: …" --entitlements …`
   majd telepítés Xcode-ból / `ios-deploy`-val.
3. **TrollStore** (ha a készülék támogatja) — aláírás nélkül is telepíti.

iOS 27.0 vagy újabb kell a készüléken.

## Újraépítés

```bash
# 1) push a main ágra (bármely fájl) → a workflow lefut
git -C ~/cortex-ai-ios push origin main

# 2) az artifact letöltése (gh vagy a web UI)
gh run download -R CortexAnime/cortex-ai-ios -n CortexAI-ipa
```

A workflow a `CortexAnime/cortex-ai-ios` repóban van, a `xcode-27` runneren fut.
Ha egy jövőbeli runner SDK-ja 27.0 alatt lenne, a „Clamp deployment target" lépés
automatikusan az elérhető SDK-hoz igazítja a célt, így a build nem áll meg.

## Ismert korlátok

- Nincs kódszignálás és nincs `.mobileprovision` — ez szándékos, a szignálás a telepítőnél történik.
- A `dv7vdbjs8q-spec/cortexai-build` tükör-repó ugyanazt a forrást tartalmazza, de azon a fiókon
  az Actions számlázás hibás („recent account payments have failed"), ezért a build a
  `CortexAnime` fiókon fut.
- iPad oldalsávhoz és a meglévő `/app`-hoz nem nyúltunk.
