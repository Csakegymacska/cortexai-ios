# Cortex AI 5.0 (build 22) — új ikon, parancspaletta, mentett utasítások, export

| | |
|---|---|
| verzió | 5.0 (22) |
| bundle id | `eu.cortex.ai` |
| minimum iOS | 27.0 (a build-szkript a helyi SDK-hoz igazítja) |
| Swift-fájl | 39 · 7 400+ sor |
| állapot | kód kész; IPA a `Scripts/build_ipa.sh`-val vagy CI-vel |

## Új ikon

A régi ikon vékony neonvonalakból állt fekete alapon. 60×60 ponton — ami a valódi
méret a home screenen — a vonalak eltűntek, és maradt egy sötét folt.

Az új ikon kitöltött formákra épül: **egy „C" alakban nyíló, vastag színátmenetes
gyűrű**, közepén izzó maggal. Nincs benne 40 px-nél vékonyabb elem, ezért kicsiben is
olvasható. Három megjelenés készül:

- `appicon-1024.png` — alap
- `appicon-1024-dark.png` — sötét mód
- `appicon-1024-tinted.png` — színezhető (iOS 18)

Mindhárom **alpha-csatorna nélkül**, mert az App Store az átlátszóságot elutasítja.
Az ikon generátora `Scripts/make_icon.py` — szín vagy arány változtatásához nem kell
grafikus.

## Parancspaletta

A fejlécben a `⌘` gomb: minden, amit az app tud, egy kereshető listán — új beszélgetés,
mély kutatás, ügynök mód, két hangnem, előfizetés, mentett utasítások, export,
beállítások, és a legutóbbi 40 beszélgetés. A keresés saját pontozású: cím eleji
egyezés 100, címben benne 70, alcímben 40, kulcsszóban 35 pont — így gépelés közben
a legvalószínűbb sor kerül felülre. Nyilakkal/Enterrel is megy.

Ez egyben szerkezeti változás is: eddig **nyolc külön `@State`** és nyolc sheet-modifier
tartotta nyilván a nyitott lapot. Most **egy `AppSheet` enum** van az `AppState`-ben, és
egy `.sheet(item:)` router — így a palettából is bármelyik lap megnyitható.

## Mentett utasítások

A napi használatban ugyanaz az 5–6 utasítás megy mindig. Itt egyszer elmented, onnantól
egy koppintás — a szöveg a szerkesztőbe kerül, **nem küldi el magától**, hogy még lehessen
igazítani. Öt kezdő utasítással indul (összefoglaló, fordítás, nyelvtan, egyszerű
magyarázat, kódreview). A használat számolódik, így a gyakran használtak előre kerülnek.
Swipe-pal szerkeszthető és törölhető.

## Exportálás

Három formátum: **Markdown** (jegyzetbe, Notionba), **sima szöveg** (e-mailbe),
**JSON** (scriptnek). Opcionálisan a réteggel és időzítéssel együtt, illetve a legutóbbi
hibával — hibajelentéshez. A fájl a Documents könyvtárba kerül (Files appból elérhető),
és a share sheet is felkínálja.

## Felület és animáció

- **A háttér két rétegen világít.** Egyetlen gradiensekből a fény „korongnak" látszott;
  most széles halvány + szűk erős réteg olvad össze.
- **Szemcse a sávosodás ellen.** A lágy gradiensek csíkosodnak OLED-en; egy statikus,
  3%-os zajréteg eltünteti. Egyszer generálódik, nem kerül CPU-ba.
- **A napi keret sávja görgetéskor összecsuklik** — a beszélgetés tetején látszik,
  lefelé görgetve átadja a helyet a szövegnek.
- **A felhasználói buborék** vékony fehér keret helyett felülről halványuló fényt kap,
  és ibolya derengést alá — sötét háttéren az árnyék koszos lenne.

## Hibajavítás

A `project.yml` egy **nem létező `Vendor/llama.xcframework`**-ra hivatkozott — az offline
motor kivezetése után bent maradt. Ez a buildet elhasaltatta volna; kivéve. A hiányzó
`Config/CortexWidgets-Info.plist` is pótolva.

## Ami még nincs benne

- **App Store IAP**: a StoreKit-kód kész, de a termékek (`…plan.pro.monthly`,
  `…plan.max.monthly`) még nincsenek létrehozva az App Store Connectben.
- **X-fiók**: az arculat kész (`web/brand/x-avatar.png`, `x-banner.png`), a fióknyitás
  a felhasználóé.
