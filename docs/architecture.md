# Vesper Architecture (iOS)

## Overview

Vesper is a native **iOS** app (Swift + SwiftUI + Core Bluetooth) that enables AI-driven control of
a Flipper Zero. It follows clean-architecture layering with a strict separation between the model
(which only *proposes* structured commands) and the app (which *decides* what actually runs).

> Vesper began as an Android app. That codebase was retired in favor of this native SwiftUI port
> (it remains in git history). This document describes the iOS design.

## Core Principles

1. **The model proposes, the app disposes.** The AI never touches Bluetooth or raw device
   primitives. It only issues structured `execute_command` tool calls.
2. **One command interface.** All operations go through a single, well-defined tool
   (`docs/execute_command_schema.json`).
3. **Diffs before writes.** Any modification to an existing file shows a diff before execution.
4. **Confirm only when necessary.** Reads and safe writes happen silently; destructive operations
   require confirmation, and irreversible ones *always* do.
5. **Everything is logged.** All agent actions are auditable and exportable.

## Layers

```
┌──────────────────────────────────────────────────────────────┐
│ Presentation — SwiftUI (TabView)                             │
│   Chat · Device · Audit · Settings   (+ @Observable state)   │
├──────────────────────────────────────────────────────────────┤
│ Agent / AI                                                   │
│   VesperAgent      — agentic tool loop, approval pause/resume │
│   OpenRouterClient — URLSession, retry/backoff, tool schema   │
├──────────────────────────────────────────────────────────────┤
│ Domain                                                       │
│   CommandExecutor  — risk gating + approval + execution       │
│   RiskAssessor · PermissionService · AuditService · Diff      │
├──────────────────────────────────────────────────────────────┤
│ Transport / Data                                             │
│   FlipperFileSystem — path-validated file ops                 │
│   FlipperProtocol   — actor; CLI framing over BLE serial      │
│   FlipperBLEManager — Core Bluetooth, chunked writes          │
│   SettingsStore (Keychain) · PersistenceController (SwiftData)│
└──────────────────────────────────────────────────────────────┘
```

## Concurrency & Safety by Construction

- **BLE transport** runs on the main actor (Core Bluetooth with `queue: nil`); inbound
  notification bytes are published through a *single* `AsyncStream`, so there is exactly one reader
  downstream. This structurally avoids the data race the retired Android build had on its shared
  response buffer.
- **`FlipperProtocol` is an `actor`** — its buffer and command lock are actor-isolated; commands
  are serialized (one in flight at a time).
- **Secrets** (the OpenRouter API key) live in the **Keychain**, never plaintext.
- **Command construction** rejects control characters and validates paths, so the line-oriented
  CLI can't be injection-abused.
- **Risk classification** parses the *full* CLI command across chained separators, enforces
  operation modes, and never auto-approves irreversible actions.

## Risk Classification

```
Command → RiskAssessor.assess(mode, unlocks)
  ├─ mode blocks action?           → BLOCKED
  ├─ touches protected path?       → BLOCKED (unless an active unlock covers it)
  ├─ execute_cli?                  → classify full command across ; && || |
  └─ per-action tier:
       LOW    → auto-run
       MEDIUM → show diff / confirm (auto if enabled)
       HIGH   → hold-to-confirm (auto if enabled AND reversible)
       BLOCKED→ refused with reason
```

## Android → Swift Mapping

| Android (retired) | iOS |
|---|---|
| `FlipperBleService` (BLE + USB) | `FlipperBLEManager` (Core Bluetooth, BLE-only) |
| `FlipperProtocol.kt` (protobuf RPC) | `FlipperProtocol` actor (CLI now; protobuf on roadmap) |
| `FlipperFileSystem.kt` | `FlipperFileSystem` |
| `OpenRouterClient` (OkHttp) | `OpenRouterClient` (URLSession) |
| `VesperAgent` | `VesperAgent` (`@Observable`, `@MainActor`) |
| `CommandExecutor`/`RiskAssessor`/`PermissionService`/`AuditService`/`DiffService` | same, in Swift |
| domain `model/*` | Swift `struct`/`enum` |
| `SettingsStore` (plaintext DataStore) | `SettingsStore` (Keychain + UserDefaults) |
| Room databases | SwiftData (`PersistenceController`) |
| Hilt `AppModule` | `AppContainer` + SwiftUI `.environment` |
| Jetpack Compose | SwiftUI |

## Transport Detail (CLI)

The Flipper exposes a text REPL over its BLE serial characteristic. Vesper writes `command\r\n`,
the device echoes the line, prints output, then re-prints its prompt (`>: `). `FlipperProtocol`
sends the command, accumulates inbound bytes, strips ANSI escapes and the echo, and returns the
text before the next prompt. File writes use the `storage write` flow (stream content, terminate
with Ctrl-C). Full protobuf RPC (for GUI/screenshot/app-bridge and firmwares that need it) is a
roadmap item layered on the same transport.

## Dependencies

Foundation-only for the app target (no third-party packages): SwiftUI, Core Bluetooth, SwiftData,
Security (Keychain), Foundation. The Xcode project is generated by XcodeGen from `ios/project.yml`.
