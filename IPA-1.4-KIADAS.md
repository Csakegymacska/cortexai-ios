# Cortex AI 1.4 (build 5) — Cortex Phantom

Nem aláírt IPA (sideload: Sideloadly / AltStore / Esign saját Apple ID-vel).

| | |
|---|---|
| fájl | `CortexAI-1.4-b5-unsigned.ipa` (a workspace gyökerében is: `CortexAI-1.0.ipa`) |
| méret | 4 296 212 B |
| sha256 | `f0354daba2ac7196fc852b5cb30df5ce878cde2b9c5aaa4e258b486c2f893fcb` |
| bundle id | `eu.cortex.ai` |
| verzió | 1.4 (5) |
| minimum iOS | 27.0 · arm64 |
| CI futás | Build `41257946118` · commit `401c790` · artifact `13062849410` |

## Mi új ebben — Cortex Phantom

Az app legfelső modellje mostantól **Cortex Phantom**, és nem egy motor válaszol helyette,
hanem három menet:

1. **Vázlat** — gyors, de már a teljes kontextussal.
2. **Lektor** — szigorú ellenőrzés: mi hiányzik, mi pontatlan, mi rossz sorrendben.
3. **Végleges** — a lektor észrevételeivel újraírt válasz, amit az app streamelve kap.

Hosszú kérdés (> 240 karakter) vagy kód/számítás esetén fut le mind a három; rövid kérdésnél
a gyors út megy, hogy ne kelljen várni. Minden modellnév a worker mögött marad: a kliens csak
annyit lát, hogy *Cortex Phantom*.

### Mért eredmények (élő, nem becslés)

| kérdés | út | idő | eredmény |
|---|---|---|---|
| „Ki vagy? Egy mondatban." | gyors | **0,9 s** | „Cortex Phantom, az OmegaTech és a CortexAnime AI-ja." |
| alma/körte számítás | gyors | **1,2 s** | 7,00 € + 6,20 € = **13,20 €**, lépésekkel |
| SwiftUI 3D kártya | hárommenetes | **18,7 s** | 4 333 karakter, teljes `View` + magyarázat |
| prímszűrő + bonyolultság | hárommenetes | **47 s** → optimalizálva | teljes kód, `math.isqrt`, buktatók |

Az első körben 90 másodperc volt egy kódkérdés; a lektor-modell cseréje és a vázlat 700 tokenre
szorítása után lett 18–22 másodperc.

## Ami az appban látszik

- **Beállítások → Model**: a Cortex Phantom az első, és az alapértelmezett (a Personal és a Code
  profil is ezt használja). A Cortex Void / Deep / Fast megmarad, ha valaki gyorsabbat akar.
- **Üres chat**: a fejléc már az aktív modell nevét és saját leírását mutatja
  (*„Három menetben gondolkodik, mielőtt válaszol"*).
- A korábbi verziókból megmarad: Memory, Cortex Void Core panel, képstúdió, profilok.

## Telepítés

1. töltsd le a `.ipa`-t (gyökér: `CortexAI-1.0.ipa`, vagy `cortexai-ios/build/`)
2. Sideloadly / AltStore / Esign → saját Apple ID → install
3. első indítás: onboarding → chat. A modellváltás a fejléc jobb felső menüjében vagy a
   Beállításokban.

A korábbi `1.3 (b4)`, `1.2 (b3)` és `1.1 (b2)` IPA törölve — csak ez a fájl van meg.
