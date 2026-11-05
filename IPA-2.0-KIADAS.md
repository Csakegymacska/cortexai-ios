# Cortex AI 2.0 (build 7) — mozgás, hang, fázisok

Nem aláírt IPA (sideload: Sideloadly / AltStore / Esign saját Apple ID-vel).

| | |
|---|---|
| fájl | `CortexAI-2.0-b7-unsigned.ipa` (workspace gyökér) |
| méret | 4 437 602 B |
| sha256 | `0d2b021b250e0ab9d3cc484f8a6845c9913cf41705703d3e5f9bcf5e858cfc14` |
| bundle id | `eu.cortex.ai` |
| verzió | 2.0 (7) |
| minimum iOS | 26.5 · arm64 |
| CI futás | `41333105822` · commit `953dac6` · artifact `13093859710` |

## Mi új ebben

**A mozgás.** Eddig minden statikus volt: a buborékok beugrás nélkül jelentek meg, a
gombok nem válaszoltak érintésre, a háttér egy fekete kép. Most van egy mozgásrendszer
(`Motion.swift`): három rugó, lépcsőztetett belépő animáció, nyomás-visszajelzés minden
gombon, shimmer a csontvázakhoz. Mindegyiknek van Reduce Motion ága, tehát aki kevesebb
mozgást kér a rendszertől, az animáció helyett vágást kap.

**Az élő háttér.** `AmbientAura` — három lámpa lebeg a beszélgetés mögött Canvasen. A tempó
és a szín az állapotot követi: gondolkodás közben gyorsabb ibolya/magenta, írás közben cián,
mikrofonnal zöldre vált. A rajzolás költsége nem nő a beszélgetés hosszával.

**Fázisok.** A composer fölött megjelenő pirula kimondja, mit csinál a modell: *Thinking*,
majd *Writing*. Az első token előtt csontváz-sorok villognak, a streamelő válasz végén
kurzor pulzál, és pontosan a stream végén tűnik el.

**Hangbevitel.** `Dictation` — `SFSpeechRecognizer` + `AVAudioEngine`, élő részeredményekkel.
Ahol a telefon tudja, a felismerés a készüléken fut (`requiresOnDeviceRecognition`), a hang
nem megy fel. A mikrofon ikon pulzál, öt sáv válaszol a hangszintedre, a szöveg ugyanabban
a mezőben jelenik meg, amit gépelésre használsz.

**Üzenet-műveletek.** Kész válasz alatt: másolás visszajelzéssel, **újragenerálás**,
megosztás és **elágazás** — a beszélgetés adott pontjáról új szál nyílik, az eredeti megmarad.

**Egyéb.** A küldés gomb rugóval vált stop-pá, a composer fénye a beíráshoz igazodik, a
transcript alján felugrik egy „ugrás a legújabbhoz" gomb, ha elgörgettél, az üres képernyő
prompt-jai lépcsőzve érkeznek.

## Javított build-hiba

Az előző, október 31-i CI-futás azért bukott meg, mert az `Info.plist`-ben a
`MinimumOSVersion` fixen `27.0` volt, miközben a runner szimulátora iOS 26.5-öt tud — a
workflow deployment-target „clampelése" ezért hatástalan volt. Most a kulcs
`$(IPHONEOS_DEPLOYMENT_TARGET)`, így a build mindig a futó SDK-hoz igazodik.

## Ami még nincs benne

- **Csatolmányok** (fotó, PDF, kamera): az app oldalán megvan a terv, de a `/chat`
  végpontnak multimodalitást kell tudnia. Amíg a szerver nem tud képet fogadni, csak dísz.
- **Forrás-chipek**: a worker keres, de nem küldi vissza strukturáltan a forrásokat.
- **Felolvasás (TTS).** `AVSpeechSynthesizer`, fél nap, szerver nélkül megoldható.
- **Widget / Live Activity.**

A részletes, kutatásra épülő listát lásd: `CORTEX-AI-2.0-TERV.md`.
