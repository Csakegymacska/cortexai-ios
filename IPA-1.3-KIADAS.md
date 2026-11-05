# Cortex AI 1.3 (build 4) — kiadás

Nem aláírt IPA (sideload: Sideloadly / AltStore / Esign saját Apple ID-vel).

| | |
|---|---|
| fájl | `CortexAI-1.3-b4-unsigned.ipa` (a workspace gyökerében is: `CortexAI-1.0.ipa`) |
| méret | 4 294 861 B |
| sha256 | `03ca8f494e09d5ca149c168828c1d5fb755e253ec26045e0c1873a69daffad98` |
| bundle id | `eu.cortex.ai` |
| verzió | 1.3 (4) |
| minimum iOS | 27.0 |
| architektúra | arm64 |
| CI futás | `CortexAnime/cortex-ai-ios` · Build `41241871685` · commit `313b669` |
| artifact | `CortexAI-ipa` `13058255637` |

## Mi új ebben — a memória, ami megmarad

A panasz: „nem jegyzi meg, amit a chatbe írsz, mindig elfelejti". Három külön hiba volt
egymásra rakva, mind a három javítva:

**1. A beszélgetés nem élt túl egy újraindítást.**
A tároló betöltése minden mezőt kötelezőnek vett: amikor egy új verzió új beállítást
vezetett be (pl. `memoryEnabled`), a régi fájl dekódolása elhasalt, a `load()` csendben
visszatért, és az app **üres chatlistával** indult — majd a következő mentés felülírta a régit.
Most minden mező opcionális, van egy második biztonsági másolat (`cortex-ai-store.backup.json`),
az olvashatatlan fájl `cortex-ai-store.damaged-<idő>.json` néven megmarad, és a
félbeszakadt válaszok (`isStreaming`) induláskor lezáródnak.

**2. A folyamatban lévő válasz elveszett.**
Eddig csak a válasz **befejezésekor** íródott ki a tároló. Most 1,5 másodpercenként ment
írás közben, és az app háttérbe kerülésekor (`scenePhase`) is.

**3. Nem volt semmi, ami az asszisztenssel együtt utazott volna.**
A history csak a folyó beszélgetés volt, és a worker 40 üzenetnél elvágta. Most van
**Memory**: a saját szavaidból kiemelt tartós tények (név, kedvencek, tervek) minden
kérésnél mennek, akárhány beszélgetés és újraindítás után is.

## Memory — hogyan működik

- **Automatikus**: ha olyat írsz, ami tartós tény („a nevem…", „a kedvenc…", „jegyezd meg",
  „szeretem", „célom…", „dolgozom…"), az app elmenti. Kérdésekre és csevegésre nem.
- **Kézi**: Beállítások → Memory → bármit beírhatsz, és törölhetsz / „Forget everything I said".
- **Kapcsoló**: `Remember useful details` — kikapcsolva semmit nem küld és nem is ment.
- A worker `memory[]` mezőként kapja, és system üzenetként fűzi a beszélgetés elé:
  *„Amit a felhasználóról biztosan tudsz… használd magától, ne kérdezz vissza rájuk."*

## Ellenőrizve (élő, nem csak fordult)

- worker, memória nélkül: „Nem ismerem a nevedet és a kedvenc animédet." → memóriával:
  „Bence vagy, és a kedvenc animéd a Frieren."
- iOS: unit tesztek zöldek (10 teszt, köztük a memória-kinyerő és a régi tároló betöltése),
  device build + IPA a CI-ből, a binárisban benne van a `Remember useful details` szöveg.
- Windows 2.1 ugyanezt tudja: a chat, a history és a memória a
  `%APPDATA%\CortexAI\chat.json`-ban, indításkor visszatöltve — restart után is emlékszik.

## Telepítés

1. töltsd le a `.ipa`-t (workspace gyökér: `CortexAI-1.0.ipa`, vagy `cortexai-ios/build/`)
2. Sideloadly / AltStore / Esign → saját Apple ID → install
3. első indítás: onboarding → Settings → Memory (ott látod, mit jegyzett meg)

A korábbi `1.2 (b3)` és `1.1 (b2)` IPA törölve, csak ez a fájl van meg.
