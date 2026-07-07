```
 ██╗   ██╗ ██████╗ ███████╗██████╗ ███████╗██████╗
 ██║   ██║╚════██╗██╔════╝██╔══██╗██╔════╝██╔══██╗
 ██║   ██║ █████╔╝███████╗██████╔╝█████╗  ██████╔╝
 ╚██╗ ██╔╝ ╚═══██╗╚════██║██╔═══╝ ██╔══╝  ██╔══██╗
  ╚████╔╝ ██████╔╝███████║██║     ███████╗██║  ██║
   ╚═══╝  ╚═════╝ ╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝
```

# V3SP3R — The AI Brain for Your Flipper Zero (iOS)

> **Talk to your Flipper Zero like it's your partner-in-hacking.** Vesper turns your pocket
> hacking tool into an AI-powered command center — controlled entirely through natural language
> from your iPhone.

No menus. No manuals. Just natural language prompting.

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)
[![iOS](https://img.shields.io/badge/iOS-17%2B-black.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)

> **Platform note:** Vesper is a **native iOS app** (Swift + SwiftUI + Core Bluetooth). It was
> previously an Android app; that codebase has been retired (it lives on in git history) and the
> project is now an iOS-first SwiftUI port. See [Status & Roadmap](#status--roadmap) for what's
> built today versus what's coming.

---

## Why Vesper?

The Flipper Zero is one of the most versatile hardware hacking tools ever made — but navigating its
menus and managing files by hand is tedious. **Vesper eliminates the friction.** Plug in an AI
brain via OpenRouter, connect over Bluetooth, and you have a voice-commanded hardware lab in your
pocket.

- **Instant expertise** — Don't memorize commands. Just say what you want.
- **Real-time control** — The AI reads your Flipper's state, executes commands, and reports back.
- **Safety-first architecture** — Every AI action is risk-classified. Destructive operations
  require explicit confirmation. Protected paths (internal storage, firmware) are locked by default.
- **Secrets in the Keychain** — Your OpenRouter key is stored in the iOS Keychain, never in plaintext.

Whether you're a security researcher, a red teamer, a CTF competitor, or a hardware tinkerer —
Vesper makes the Flipper Zero *dramatically* more accessible.

---

## Status & Roadmap

This repository is the **foundation** of the iOS app: a buildable, testable core. It is being
grown to full feature parity with the retired Android app over subsequent passes.

### Working today
- **BLE transport** — scan, connect, and talk to a Flipper over Core Bluetooth (BLE-only on iOS).
- **AI agent** — natural-language chat → OpenRouter tool calls → risk-gated execution.
- **Risk & approval engine** — LOW auto-runs; MEDIUM shows a diff; HIGH needs a 1.5s hold;
  protected paths are BLOCKED until unlocked. Irreversible actions always require confirmation.
- **File & device operations** — list/read/write/mkdir/delete/rename/copy on `/ext`, plus device
  info, storage info, LED, vibro, and app launch — all over the Flipper CLI.
- **Audit log** — every action recorded; export as JSON.
- **Screens** — Chat, Device, Audit, Settings.

### On the roadmap
- Full protobuf RPC (GUI/screenshot/app-bridge) alongside the CLI path.
- Hardware actions: SubGHz/IR/NFC/RFID/iButton transmit & emulate, BadUSB, payload forging.
- Multimodal: voice (Speech framework) and camera/vision input.
- More screens: Alchemy Lab, Payload Lab, Signal Arsenal, Spectral Oracle, Device Tracker, FapHub.
- Smart-glasses bridge (the `mentra-bridge/` relay) with authentication hardening.

---

## Quick Start

### Requirements

| Item | Notes |
|------|-------|
| **Flipper Zero** | [shop.flipperzero.one](https://shop.flipperzero.one) — Bluetooth enabled |
| **iPhone** | iOS 17+ |
| **Mac + Xcode 15+** | To build/run (there is no App Store build yet) |
| **OpenRouter account** | Free signup, pay-per-use — [openrouter.ai](https://openrouter.ai) |

### Build

The Xcode project is generated from `ios/project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(so the `.xcodeproj` is not committed):

```bash
brew install xcodegen
cd ios
xcodegen generate
open Vesper.xcodeproj
```

Then pick an iPhone simulator (or your device) and hit **Run**. To build from the command line:

```bash
cd ios
xcodegen generate
xcodebuild -project Vesper.xcodeproj -scheme Vesper \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build test CODE_SIGNING_ALLOWED=NO
```

CI runs exactly this on every push (`.github/workflows/ios.yml`).

### First launch
1. **Add your API key** — Settings tab → paste your OpenRouter key (starts with `sk-or-`). It's
   saved to the Keychain.
2. **Connect** — Device tab → Scan → tap your Flipper.
3. **Go** — Chat tab → start talking to your Flipper.

---

## Architecture

Native Swift, clean layering, with concurrency safety by construction (Bluetooth callbacks on the
main actor + a single inbound `AsyncStream`; secrets in the Keychain; an actor-serialized CLI).

```
SwiftUI (TabView: Chat · Device · Audit · Settings)
  └─ VesperAgent (@Observable) — agentic tool loop, approval pause/resume, immutable snapshots
       ├─ OpenRouterClient (URLSession, retry/backoff, tool schema, tolerant parsing)
       └─ CommandExecutor — "the app decides" → RiskAssessor → PermissionService → AuditService
            └─ FlipperFileSystem (path validation) → FlipperProtocol (actor, CLI framing)
                 └─ FlipperBLEManager (Core Bluetooth, chunked writes, single inbound stream)
Data: SettingsStore (Keychain + UserDefaults) · PersistenceController (SwiftData)
```

See [docs/architecture.md](docs/architecture.md) for the full map and the Android→Swift mapping.

## Project Structure

```
ios/
├── project.yml                 # XcodeGen spec
├── Vesper/
│   ├── App/                    # entry point, DI container, Info.plist, assets
│   ├── Core/
│   │   ├── BLE/                # FlipperBLEManager, FlipperProtocol, FlipperFileSystem
│   │   ├── AI/                 # OpenRouterClient, VesperAgent, VesperPrompts
│   │   ├── Domain/             # RiskAssessor, CommandExecutor, services, models
│   │   └── Data/               # SettingsStore (Keychain), Persistence (SwiftData)
│   └── Features/               # Chat, Device, Audit, Settings (SwiftUI)
└── VesperTests/                # XCTest: risk, approval, parsing, framing
docs/                           # architecture + execute_command schema + system prompt
mentra-bridge/                  # smart-glasses relay (Node) — roadmap
```

---

## Safety & Legal

- Vesper is a tool for **education and legitimate security research**.
- Only use on devices you own or have explicit authorization to test.
- All AI actions are logged and auditable.
- Destructive operations require explicit user confirmation; irreversible ones always do.
- You are responsible for complying with all applicable laws in your jurisdiction.

## Security

Found a vulnerability? Please report it responsibly. See [SECURITY.md](SECURITY.md).

## Contributing

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

GPL-3.0 — see [LICENSE](LICENSE).

---

**V3SP3R** — AI-powered hardware hacking, in your pocket. Your Flipper Zero just got a brain upgrade.
