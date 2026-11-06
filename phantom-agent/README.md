# Cortex Phantom Agent — natív iOS app az Arena API-hoz

A böngészőlap helyett natív app: **teljesen natív chat a hivatalos Arena API-n**
(`api.arena.ai`, OpenAI-kompatibilis), plusz az agent-munkaterület és az élő állapot:

- **Dynamic Island** — élőben mutatja, hogy az agent dolgozik, és éppen mit bash-el
  (`Working: python3 tools/…` + eltelt idő);
- **Widget** — kezdőképernyőn az állapot egy pillantásra;
- **Animációk** — aurora-háttér, pulzáló gyűrű, rugós buborékok, élő stream-caret;
- **Stílus** — sötét/violet dizájnvonal, angol UI, emoji nélkül; egyedi logo.

**Követelmény:** iOS 26.0+, iPhone (Dynamic Island eszközökön teljes élmény).

## Felépítés

```
arena-ios/
  project.yml            XcodeGen spec (app + widget kiterjesztés)
  ArenaApp/              az app: SwiftUI ház + WKWebView chat-felület
    ArenaApp.swift       belépés + BGAppRefresh (háttérben is frissíti a szigetet)
    ContentView.swift    fejléc, web-felület, élő lépéssáv ("mit bash-elek")
    WebView.swift        WKWebView — session megmarad, újracsatlakozás
    StatusClient.swift   állapot-poll (5 mp)
    ActivityManager.swift Live Activity indítás/frissítés
    Theme.swift          dizájn-rendszer (színek, gombok, StatusPill)
    SettingsView.swift   Arena URL, állapot-híd, megjelenés
  ArenaWidget/           widget kiterjesztés
    AgentLiveActivity.swift  Dynamic Island (minimal/compact/expanded) + zárt képernyő
    StatusWidget.swift       kezdőképernyő widget (small/medium)
  Shared/                app + widget közös modell
    AgentStatus.swift
    AgentActivityAttributes.swift
```

## Építés

```bash
brew install xcodegen
cd arena-ios && xcodegen generate
open ArenaAgent.xcodeproj      # Xcode 27+, iOS 27 SDK
# unsigned IPA a megszokott csatornára (mint a CortexAI iOS)
```

## Az állapot-híd (ez táplálja a Dynamic Islandet)

1. Az agent munka közben jelent: `python3 tools/agent_status.py "bash: <parancs>"`.
2. A `cortexai-api` worker eltárolja: `POST /api/cortexai/agent/status` (token:
   `AGENT_STATUS_TOKEN`), R2 `cortexai/agent/status.json`.
3. Az app 5 mp-enként pollolja a `GET`-et; ha `working`, frissíti a Live Activityt —
   a Dynamic Island élőben mutatja a lépést és az eltelt időt.
4. Háttérben a `BGAppRefresh` (`eu.cortex.arena.status`) tovább frissít.

A teljes architektúra és a v2-es tervek (APNs push, natív chat API esetén):
`ARENA-NATIVE.md` a workspace gyökerében.
