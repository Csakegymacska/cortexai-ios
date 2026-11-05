# Cortex AI 7.0 (build 24) — chat-átépítés, teljes iOS 26-os dizájn

| | |
|---|---|
| verzió | 7.0 (24) |
| minimum iOS | 26.0 |
| fókusz | chat újrarendezése + jobb dizájn + animációk |

## Mi változott

**Chat újrarendezve.** A válaszok többé nem „dokumentumként" terülnek szét: minden
Cortex-válasz egy lebegő **üveg kártyán** ül, mellette a jelvény légző fénnyel —
valódi beszélgetés-ritmus. A kártya éle fény-gradiens, streaming alatt a jelvény
izzik, a műveletek (másolás, felolvasás, újra) kártya alatt külön sorban.

**Gombok.** Minden ikon-gomb `LiquidPress` stílusú: nyomásra finoman megnyúlik,
mint egy vízcsepp — ez az iOS 26-os interakciós nyelv.

**Küldés gomb.** Küldhető állapotban a márkagradiens tölti ki, fehér üveg-gyűrűvel;
streaming alatt visszavált a leállítás-gombra.

**Előző körök (6.x):** parancspaletta, mentett utasítások, export, `AppSheet`
router, új app ikon (3 megjelenés), AmbientAura háttérfény, üveg composer és fejléc.
