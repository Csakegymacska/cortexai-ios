# Cortex AI 1.2 (build 3) — kiadás

Nem aláírt IPA (sideload: Sideloadly / AltStore / Esign saját Apple ID-vel).

| | |
|---|---|
| fájl | `CortexAI-1.2-b3-unsigned.ipa` (a workspace gyökerében is) |
| méret | 4 262 833 B |
| sha256 | `d2de384545eb89e8684d5e7ea3526df303f0baa0f7d101cc3d1dfe1d11bc9ed8` |
| bundle id | `eu.cortex.ai` |
| verzió | 1.2 (3) |
| minimum iOS | 27.0 |
| architektúra | arm64 |
| CI futás | `CortexAnime/cortex-ai-ios` · Build `41237084686` · commit `88cb5d6` |
| artifact | `CortexAI-ipa` `13055573423` |

## Mi új ebben

**Cortex Void Core panel** (Beállítások → *Cortex Void Core*)

- fázis-jelvény: `Learning`, amíg a saját modell a 92 pontot nem éri el, utána `Ready`
- körszámláló és pontszám: `Round 0 · 0.0 of 92 points`
- folyamatjelző sáv a célhoz képest
- három mérő: **Identity**, **Catalogue**, **Hungarian** (a vizsga részpontszámai)
- bajnok-sor: `Champion v… · gate +0.02 points to take the crown`
- a következő kör ideje: `Nightly round 03:15 UTC`
- `Serving your replies from our own cluster.`, ha a saját modell már kiszolgál

A panel a `GET /api/cortexai/core` végpontot olvassa, ami **csak számokat** ad vissza:
nincs benne bázis-modell, adapter-útvonal, szolgáltató vagy token-szám. Ha a hurok még nem
futott, a panel `Round 0 · 0.0 of 92` állapotot mutat — nem hibát.

## Hogyan készült

- `xcodegen` + `xcodebuild` az `xcode-27` runneren (iOS 27 SDK), Xcode 27.1
- unit tesztek: 5/5 zöld a szimulátoron a device build előtt
- aláírás nélküli Release build → `Payload/CortexAI.app` → `zip -qry`

## Telepítés

1. töltsd le a `.ipa`-t (workspace gyökér vagy `cortexai-ios/build/`)
2. Sideloadly / AltStore / Esign → saját Apple ID → install
3. első indítás: onboarding, majd a chat

A korábbi `1.1 (b2)` IPA-t felváltja; az 1.0-s fájl törölve.

## Ellenőrzés a fájlon (CI után, helyben)

```
CFBundleIdentifier            eu.cortex.ai
CFBundleShortVersionString    1.2
CFBundleVersion               3
MinimumOSVersion              27.0
UIRequiredDeviceCapabilities  [arm64]
bináris                       2 277 232 B, arm64
tartalmazza                   "Cortex Void Core", "cortanime.eu"
sha256                        egyezik a CI által írt .sha256-tal
```
