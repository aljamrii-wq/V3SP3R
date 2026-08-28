# V3SP3R (Vesper) — Verified Security & Correctness Audit

**Method:** Re-audited with four Sonnet 5 verifier agents (verify-or-refute against candidate findings) **plus** first-hand source review of every load-bearing file. Every finding below is CONFIRMED against the current tree (HEAD `0d95f2c`); none was refuted. Read-only — no code changed.

Each numbered section is self-contained and issue-ready (title + body); severity is in the title. Findings are ranked most-severe first: 3 Critical, 7 High, 4 grouped Medium/Low.

---

## 1. [Critical] `execute_cli` bypasses protected-path, operation-mode, and irreversible-approval gates

`execute_cli` evades all three safety layers, and since every structured hazard action is a stub (`CommandExecutor.swift:155-158`), it is the **only path wired to hardware** in this build.

- **Protected-path gate ignores CLI content.** `affectedPaths()` (`RiskAssessor.swift:134-138`) only reads `args.path/.destinationPath/.signalFile`, never `args.command`, so the gate loop (`RiskAssessor.swift:32-36`) is empty for CLI.
- **Mode blocklist is keyed on `CommandAction`.** `OperationMode.blockedActions` (`RiskLevel.swift:48-62`) contains only structured actions; `.executeCli` is never in it, so the check at `RiskAssessor.swift:27` can't block it. Stealth/Recon RF guarantees do not cover CLI.
- **Unknown verbs → MEDIUM; CLI excluded from the irreversible gate.** `classifyCli` falls to `.medium` (`RiskAssessor.swift:104`); `requiresApproval` (`CommandExecutor.swift:95-97`) auto-approves HIGH unless `action.isIrreversible`, and `.executeCli` is not in that set (`Command.swift:36-43`). Sink does no validation (`FlipperFileSystem.swift:105-108`).

**Exploits (airtight):**
- `execute_cli {command:"storage read /int/dolphin_data"}` → LOW, auto-runs, reads protected internal storage that structured `read_file /int/...` would BLOCK.
- With auto-approve-high on: `execute_cli {command:"storage remove_recursive /ext/x"}` → HIGH but auto-approved (contradicts `CommandExecutor.swift:87` and the Settings copy); structured `.delete` runs the identical wire command yet is always gated. Untested interaction.

**Related:** `.move`/`.rename` share the same auto-approve gap (HIGH, not in `isIrreversible`).

**Fix:** parse verb+paths out of `args.command` and run them through the protected-path/mode/irreversible checks (or route storage through structured actions and allowlist `execute_cli`); default unknown verbs to HIGH/BLOCKED; thread the full `RiskAssessment` into `requiresApproval`; add tests.

---

## 2. [Critical] mentra-bridge accepts unauthenticated clients; role assigned by first message type

No token/HMAC/session-secret/TLS check anywhere (`mentra-bridge/src/index.ts`, `glasses-adapter.ts`). Role from a public header (`index.ts:212-213`), then `unknown` clients are promoted by first message type (`index.ts:259-340`):
- `VOICE_*` → `glasses` → injected into the agent as user speech (264-274).
- `CAPTURE_REQUEST` → `vesper` → `captureAndAnalyze` → remote glasses camera (316-325, 938-942).
- `AI_RESPONSE`/`STATUS_UPDATE` → `vesper` → `speakWithEchoGuard`/`session.audio.speak` → arbitrary TTS on the victim's glasses (307-314, 875-887).
- `CONFIG` has no role check → any socket flips global mute/sailor-mouth (327-338).

Any client reaching `ws://<host>:8089` (no TLS) can do the above with a single frame. Also missing: `maxPayload` (`index.ts:184`, ws default ~100 MiB), `Origin` validation (CSWSH), and rate limiting.

**Fix:** require a per-deployment secret/token on connect; reject unauthenticated sockets before processing; bind role by verified credential; add `maxPayload`/Origin/rate-limit; keep iOS `glassesBridgeURL` unwired until done.

---

## 3. [Critical] BLE write-ack has no timeout → one dropped ack permanently deadlocks the command queue

`writeChunk` (`FlipperBLEManager.swift:153-159`) awaits a continuation resumed only by `didWriteValueFor`/`teardown`, with no timer. `sendCommand`'s deadline (`FlipperProtocol.swift:56-62`) is checked only **after** `transport.send` returns (line 52), so a hung `.withResponse` write never times out; the `defer { release() }` (line 48) never runs; `commandInFlight` stays true; every later `acquire()` blocks forever. Only an app restart recovers (one long-lived actor, `AppContainer.swift:22-23`). Trigger: a dropped GATT write-response with no accompanying disconnect callback.

**Fix:** race `writeChunk`'s continuation against a timeout; make `sendCommand`'s timeout cover send+wait; add a mockable Core Bluetooth seam and a stalled-write test.

---

## 4. [High] Unknown CLI verbs default to auto-approvable MEDIUM

`classifyCli` fallback returns `.medium` (`RiskAssessor.swift:104`) for any verb not in the small curated lists (gpio/i2c/spi/subghz/ir/nfc/badusb/loader…). MEDIUM is auto-approved when `autoApproveMedium` is on (`CommandExecutor.swift:94`). Note: `autoApproveMedium` defaults to false (opt-in), but once enabled every unrecognized verb — including live hazard commands via `execute_cli` — runs with no gate. **Fix:** unrecognized verbs default to HIGH/BLOCKED with an explicit LOW/MEDIUM allowlist.

---

## 5. [High] NFC/RFID/iButton/IR emulation classified MEDIUM (not irreversible) vs `subghz_transmit` HIGH

`RiskAssessor.swift:51-54` buckets `irTransmit`/`nfcEmulate`/`rfidEmulate`/`ibuttonEmulate` as MEDIUM alongside `led_control`, while the functionally-equivalent `subghzTransmit` is HIGH+irreversible (`:59-60`, `Command.swift:38`). Emulating a badge/key that opens a door isn't reversible. Currently **latent** (these are stubs), so today it's only reachable through the CLI path's own weak classification — but the structured-action risk table would allow AI-issued emulation on a toggle once wired. **Fix:** reclassify these HIGH + irreversible before hardware wiring.

---

## 6. [High] CLI framing: prompt `">: "` matched anywhere in the buffer truncates/corrupts reads

`extractResponse` (`FlipperProtocol.swift:87-98`) uses `range(of: ">: ", options: .backwards)` with no end-of-buffer/`hasSuffix` check, evaluated every 40ms against partial data. A response whose content contains `">: "` truncates at that point and releases the lock while the device is still transmitting; the straggling tail can be appended into the next command's buffer (`ingest` runs continuously; the next `sendCommand` clears only at its own start, `:50/:70`). **Fix:** require a quiescence window and/or `hasSuffix(prompt)`; ideally frame with a unique per-command sentinel.

---

## 7. [High] 512KB CLI buffer trims from the front, corrupting large reads

`ingest` (`FlipperProtocol.swift:37-43`) does `buffer.removeFirst(...)`, dropping the **oldest** bytes past 512KB. For a device response >512KB the head is lost (including the echoed command line and the `Size:` header), so `extractResponse` returns a tail slice; `readFile` then `prefix(maxBytes)`-truncates that already-wrong body and appends a misleading `[truncated]` marker (`FlipperFileSystem.swift:59-61`). Not UTF-8-boundary-aware. **Fix:** fail with an explicit error past a hard cap, or stream/chunk large reads at the protocol level.

---

## 8. [High] BLE write-without-response has no backpressure → silent chunk loss

`send` (`FlipperBLEManager.swift:137-144`) paces `.withoutResponse` writes with a fixed 12ms `Task.sleep` instead of `peripheral.canSendWriteWithoutResponse` + `peripheralIsReady(toSendWriteWithoutResponse:)` (neither exists in the tree). Under large `storage write` payloads / weak RF / background throttling, writes issued while the stack isn't ready are dropped with no error → corrupted on-device file. **Fix:** gate each write on `canSendWriteWithoutResponse`; implement the ready callback.

---

## 9. [High] No peripheral-identity check in Core Bluetooth callbacks

`connect()` (`FlipperBLEManager.swift:100-112`) doesn't cancel a prior in-flight attempt; every delegate callback (`227-313`) trusts its `peripheral:` parameter without comparing to `self.peripheral` (`pendingConnectId` is written at `:107`/`:168` but never read); characteristic selection (`270-293`) is property-only, never matched to `serialServiceHint`. A stale callback can `teardown()` a newer connection. **Fix:** cancel pending connections; `guard peripheral === self.peripheral` in every callback; prefer the known service UUID.

---

## 10. [High] mentra-bridge state is process-global, not per-session

`sailorMouthEnabled`, `glassesMuted`, `ttsSpeaking`, `lastSpokenText`, wake/task timestamps are module-level `let`s (`index.ts:73-88`), mutated by `CONFIG` (`:329-336`) and `speakWithEchoGuard` (`:875-887`) with no session scoping. On a shared deployment one user's mute/config/echo-state affects all connected users. **Fix:** key all mutable state per authenticated session.

---

## 11. [Medium] AI/agent robustness (OpenRouterClient / VesperAgent)

- **No per-turn tool-call cap and no `max_tokens`.** `runLoop` executes every returned tool call (`VesperAgent.swift:145-148`); the request body sets no `max_tokens` (`OpenRouterClient.swift:80-85`). The prompt's "max 3 commands" is advisory only. A single (possibly injected) turn can queue many auto-approved LOW reads, each re-sent in full across up to 20 iterations. Enforce a hard cap + `max_tokens`.
- **One malformed `tool_calls` element drops the whole batch.** `message["tool_calls"] as? [[String:Any]] ?? []` is all-or-nothing (`OpenRouterClient.swift:166`); can also surface as the misleading "empty response." Cast as `[Any]` + `compactMap`.
- **Tool schema sent to the model has no `args` sub-schema.** `OpenRouterClient.swift:217-220` sends only `args:{type:object}`; drifts from `docs/execute_command_schema.json`; tests only check the action enum. Build from the doc or add a diff test.
- **`RateLimiter.acquire()` busy-loops on cancellation.** Non-throwing + `try?`-swallowed `Task.sleep` (`OpenRouterClient.swift:253-265`) spins the CPU (up to 60s) when the task is cancelled. Make it `throws`, check `Task.isCancelled`.
- **`executeWithRetry` never checks cancellation** (`:101-134`) — surfaces as a generic error via incidental double-throw; also a needless backoff sleep after the final attempt.
- **`aiMaxIterations` ceiling is UI-only** (`SettingsView.swift:76-79` clamps 1...20; `SettingsStore.swift:22-23,49` accepts any Int; loop floors only, `VesperAgent.swift:107`).
- **`parseToolCall` never validates `function.name == "execute_command"`** (`:175-181`); benign with one tool, but add before a second is introduced.

---

## 12. [Medium] iOS persistence, audit durability & at-rest protection

- **Silent save/load failures + in-memory fallback.** `try? context.save()` (`Persistence.swift:86,97`); a failed on-disk container silently falls back to in-memory (`:63-68`, audit lost on relaunch, no signal); fetches swallow errors (`:104,123,131`). Contradicts the "everything is logged and auditable" claim. Log failures; surface a "persistence degraded" state.
- **No tamper-evidence / no success signal.** `AuditService.log` calls `sink?(entry)` unchecked (`AuditService.swift:26`); no hash-chain/signature on `AuditRecord`. Consider a running hash chain if the log is forensic.
- **Unbounded growth, no indexes.** `maxInMemory=200` bounds only the UI window; every audit/chat row persists forever; `sessionId`/`timestamp` predicates full-scan (`Persistence.swift:101-138`). Add retention + `#Index`.
- **No file-protection class on the SwiftData store.** `ModelConfiguration` sets only `isStoredInMemoryOnly` (`Persistence.swift:54-69`); no `.fileProtection`. Set/document `NSFileProtectionComplete…`.
- **`SECURITY.md` describes the retired Android app** (EncryptedSharedPreferences/Room/"jailbroken Android", `SECURITY.md:53-54,73`). Rewrite for iOS.
- **Keychain flag** could be the stricter `WhenUnlockedThisDeviceOnly` (`Keychain.swift:20,27`), since the key is used only in foreground.

---

## 13. [Medium] BLE transport robustness (FlipperProtocol / FlipperFileSystem)

- **Binary content mangled.** `String(decoding: buffer, as: UTF8.self)` + `stripAnsi` (`FlipperProtocol.swift:89-90,112-134`): a raw `0x1B` in file content starts an escape-eat; invalid UTF-8 → U+FFFD, both silent. Add binary detection / a hex/base64-safe read path.
- **`readFile` size cap mixes bytes and Characters** (`FlipperFileSystem.swift:59-61`): checks `utf8.count` but truncates with `String.prefix` (grapheme count) → up to ~4× overshoot feeding the LLM. Truncate on `body.utf8.prefix(maxBytes)`.
- **`deviceInfo()` swallows transport errors** (`:110-113`): three `try?` sub-commands; a mid-call disconnect returns a normal-looking result. Distinguish "field absent" from "threw."
- **Device-side CLI errors reported as success** (`:65-101`): file ops return CLI text unchecked; `CommandExecutor` treats any non-throw as `.ok`. Parse Flipper's error prefixes and throw.
- **Lows:** `teardown()` can run twice on rapid disconnect→reconnect and clobber a newer connection (`FlipperBLEManager.swift:114-117,161-170`); `retainedPeripherals` grows unbounded (`:149`); `stripAnsi` handles only CSI; `stripReadHeader` first-line heuristic is fragile both ways (`FlipperFileSystem.swift:165-172`).

---

## 14. [Medium] mentra-bridge hardening, CI & docs

- **No lockfile, no CI for the bridge.** `mentra-bridge/` has no `package-lock.json`; caret-range deps (`package.json:11-20`); `.github/workflows/ios.yml` builds only iOS — no `npm ci`/`tsc`/lint/`npm audit`. Commit a lockfile; add a bridge CI job.
- **`/health` discloses live connection counts unauthenticated** (`index.ts:956-972`).
- **Heartbeat bug:** `return ws.terminate()` (`index.ts:202`) exits the whole `setInterval` callback, skipping every client after the first dead one that tick. Use `continue`.
- **`actions/checkout@v4`** pinned by floating tag, not SHA (`ios.yml:21`).
- **`glassesBridgeURL`** is persisted but dead/unwired in the iOS app (`SettingsStore.swift:24,50,70` only) — must stay unwired until bridge auth (#2) and per-session state (#10) land.
- **Stale doc:** `docs/vesper_system.txt:62` promises `.key/.priv/.secret` blocking that no code implements (`ProtectedPaths` checks only `/int`,`/dev`,`/sys`). The live prompt `VesperPrompts.swift` already dropped the claim; fix the doc (or implement the extension rule).
- **Info:** `DeviceView.swift:128` calls `fs.deviceInfo()` directly, bypassing `AuditService` for that user-initiated read (low impact — read-only, user-initiated, not AI-initiated).

---

## Verified strengths
Trust boundary is correct (model proposes, app decides; justification/expected_effect never used for risk); `assess` switch has no `default:` (new actions must be classified); path traversal is layered and tested (`/ext/../int/secret` blocked); CLI chaining is split and escalated; structured irreversible actions can't be auto-approved (tested); secrets hygiene clean (no committed keys, Keychain-only, never logged; ATS secure default); fail-secure UI (dismiss = reject, 1.5s hold, plain-`Text` rendering, `isLoading` re-entrancy guard, `[weak self]` closures); single-`AsyncStream` BLE reader + `@MainActor`/`assumeIsolated` + actor FIFO lock releasing on every completed throw path.
