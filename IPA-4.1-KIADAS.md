# Cortex AI 4.1 (build 21) — a napi keret láthatóvá tétele

| | |
|---|---|
| verzió | 4.1 (21) |
| bundle id | `eu.cortex.cortexai` |
| minimum iOS | 27.0 (a build-szkript lejjebb veszi, ha a helyi SDK régebbi) |
| állapot | **kód kész, IPA még nincs** — nincs macOS runner (lásd lent) |

## Mi új ebben

**A keret a fejlécben.** A szerveroldali átszervezés után a legfontosabb szám a napi
tokenkeret, és eddig csak akkor derült ki, amikor 429 jött. Most a fejléc alatt egy 3 pt-os
sáv mutatja az arányt, alatta a szöveg: `Pro · 18,4 millió token maradt`. 90% felett
magenta, 99,5% felett piros. Koppintásra kinyílik az előfizetés.

**Elfogyott keret sáv.** Ha a keret elfogy, a beszélgetés tetején megjelenik egy magyarázó
sáv (nem hibaüzenet): mikor áll vissza, és hogyan lehet azonnal emelni. Magától eltűnik,
ha a szerver szerint mégis van keret.

**Frissítés körönként.** Minden válasz után az app a `/api/v1/usage`-ból olvassa vissza a
keretet — a felület soha nem számol magának, mert a keret a fióknál van, nem az eszköznél.

**Hibaszövegek.** A 401 / 402 / 429 / 503 már nem nyers HTTP-kód:
- 401 → „No API key linked yet…" + hol lehet kulcsot csinálni
- 429 → „Daily token allowance reached. It resets at midnight UTC."
- 503 → az egyenleg hiányzik, nem a felhasználó hibája

## Hogyan lesz IPA

Három út, mind a három ugyanazt a `Scripts/build_ipa.sh`-t hívja:

1. **Saját Mac** — `./Scripts/build_ipa.sh` → `out/CortexAI-4.1-b21-unsigned.ipa`
2. **GitHub Actions** — a `Build` workflow; macOS runnert kell kapnia a fióknak
3. **Cirrus CI** — `.cirrus.yml`; nyílt repókra ingyen ad macOS VM-et

A build aláíratlan, tehát Sideloadly / AltStore / Esign-nel kerül a készülékre.
