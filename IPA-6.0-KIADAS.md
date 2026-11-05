# Cortex AI 6.0 (build 23) — iOS 26, Liquid Glass

| | |
|---|---|
| verzió | 6.0 (23) |
| **minimum iOS** | **26.0** |
| **Xcode** | **26 vagy újabb (iOS 26 SDK) — kötelező** |
| Swift-fájl | 39 · ~8 000 sor |
| állapot | **IPA elkészült** (lásd lent) |

## Miért iOS 26

Az app mostantól a 26-os rendszer anyagára épül, mert az adja a legtöbb dizájn-eszközt:

**Liquid Glass.** A composer, a fejléc gombjai, a tier-választó, a keret-sáv és a
parancspaletta keresősávja valódi üveg: a beszélgetés átszűrődik alattuk, és a felület
fénytöréssel emelkedik ki. A fejléc üvegfelületei egy `GlassEffectContainer`-ben vannak,
ezért közel kerülve összeolvadnak — ez a rendszer ajánlott mintája, nem külön-külön
lerakott üvegkockák.

**Scroll edge effect.** A beszélgetés a képernyő széle felé lágyan elhalványul, ahelyett
hogy éles vonalnál elvágódna.

**Visszafelé kompatibilitás beépítve.** A `Sources/GlassCompat.swift` egy helyen dönti el,
mi történik 26 alatt: ugyanaz a felület, csak `.ultraThinMaterial`-ral. Ha később lejjebb
kell venni a deployment targetet, nem kell szétszedni a nézeteket.

## Ezért a CI is változott

A workflow most **megköveteli az iOS 26 SDK-t**, és ha a runner Xcode 16-os, inkább
azonnal megáll egy érthető üzenettel, mint hogy 20 perc után derüljön ki. Runnerek:
`macos-26` és `macos-latest` párhuzamosan; ha a képen több Xcode van, a legnagyobb
`Xcode_26.*`-ot választja.

A `Scripts/build_ipa.sh` ugyanezt teszi helyben: SDK < 26 esetén nem is kezd bele.

## Mi van benne ezen felül (5.0-ból)

- Új app ikon, három megjelenéssel (alap, sötét, színezhető), alpha nélkül
- Parancspaletta, mentett utasítások, export (Markdown / szöveg / JSON)
- `AppSheet` router: 12 lap egy helyen
- Kétrétegű háttérfény, szemcse, görgetéskor összecsukló keret-sáv
- Javítva: a `Vendor/llama.xcframework` hivatkozás és a hiányzó widget Info.plist

## Az IPA

**`kiadas/CortexAI-6.0-b23-ios18-compat-unsigned.ipa`** (3,2 MB)
sha256: `5f9df18d2b677768265bdebba0b360c696eaf8c2b56d6c0d97ced8e1dd00b2eb`

- verzió 6.0 (23), `eu.cortex.ai`, arm64, iPhone + iPad, minimum iOS 18.5
- a **widget-bővítmény benne van** (`PlugIns/CortexWidgets.appex`) és az új ikon mindhárom megjelenése is
- **aláíratlan** — telepíteni aláírással lehet (AltStore, Sideloadly, Xcode,
  vagy saját fejlesztői tanúsítvány + `ideviceinstaller`)
- **Liquid Glass nélkül**: ez a kompatibilitási build a GitHub iOS 18.5-ös SDK-jával
  készült (`COMPAT_SDK`), ezeken a felületeken a tömör anyag van. Minden más
  (funkció, animáció, ikon, paletta, export) teljes.

**Aláírás (ezt kell csak megcsinálni):**
- **Fizetett fejlesztői tanúsítvány** (Apple Developer Program, vagy aláírás-szolgáltatás
  p12-je) → Esign / Sideloadly / AltStore / `codesign`: a widgettel együtt települ.
- **Ingyenes Apple ID** → a kiterjesztés (widget) miatt a telepítés elhasal; ilyenkor
  szólj, és adok widget nélküli változatot.
- A szerszám a `.appex`-t is automatikusan aláírja; külön lépés nem kell.

**Liquid Glass-os build**: Actions → *iOS 26 build* → *Run workflow* — ehhez
Xcode 26-os runner kell (macos-26); jelenleg sorban áll a GitHub-nál. Ha a runner
SDK-ja frissebb lesz, ez az út adja a teljes 26-os felületet, szintén widgettel.

## Ami nyitott

- **IPA**: a GitHub macOS-runnerein kapacitáshiány van („The job was not acquired by
  Runner of type hosted"). Amíg ez tart: saját Mac (Xcode 26) vagy Cirrus CI
  (`ghcr.io/cirruslabs/macos-tahoe-xcode`, bekapcsolás a cirrus-ci.com-on).
- **App Store termékek**: `eu.cortanime.cortexai.plan.pro.monthly` / `...max.monthly`.
