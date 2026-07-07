# Contributing to V3SP3R

Thanks for your interest in contributing! Vesper is an open-source project and we welcome contributions of all kinds — bug fixes, new features, documentation, and more.

## Getting Started

1. **Fork** the repository on GitHub
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/V3SP3R.git
   cd V3SP3R
   ```
3. **Create a branch** for your work:
   ```bash
   git checkout -b feature/your-feature-name
   ```
4. **Generate and open the Xcode project** (see below)
5. **Build and test** your changes

### Requirements

- macOS with **Xcode 15+**
- **iOS 17+** deployment target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A Flipper Zero device (for testing hardware features)

### Generate the project

The `.xcodeproj` is generated from `ios/project.yml` (and git-ignored):

```bash
brew install xcodegen
cd ios
xcodegen generate
open Vesper.xcodeproj
```

Run the tests from the command line with:

```bash
cd ios
xcodegen generate
xcodebuild -project Vesper.xcodeproj -scheme Vesper \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build test CODE_SIGNING_ALLOWED=NO
```

## Development Guidelines

### Code Style

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- Use meaningful names; keep functions focused — one function, one responsibility
- Prefer value types (`struct`/`enum`) for models; `actor`/`@MainActor` for shared mutable state
- Follow SwiftUI best practices; use `@Observable` for view state

### Architecture

Vesper follows a layered architecture (see [docs/architecture.md](docs/architecture.md)):

- **Presentation** — SwiftUI screens + `@Observable` state (in `ios/Vesper/Features/`)
- **Agent/AI** — `VesperAgent`, `OpenRouterClient` (in `ios/Vesper/Core/AI/`)
- **Domain** — command execution, risk assessment, services (in `ios/Vesper/Core/Domain/`)
- **Transport/Data** — BLE, persistence, settings (in `ios/Vesper/Core/BLE/`, `Core/Data/`)

When adding features, place code in the appropriate layer.

### Security

Security is a core concern for Vesper. Please:

- **Never** commit API keys, secrets, or credentials (the API key belongs in the Keychain)
- **Always** validate and sanitize external input (LLM responses, BLE data, user input)
- **Respect** the risk classification system — new actions must get an appropriate `RiskLevel`
- **Never** interpolate unvalidated strings into a CLI command — reject control characters and
  validate paths (`FlipperFileSystem.validate`)
- **Test** edge cases, especially around JSON parsing and command classification

### Commit Messages

Write clear, descriptive commit messages:

```
Add SubGHz frequency validation to signal editor

Validates that user-entered frequencies fall within supported SubGHz
bands before attempting transmission. Shows an inline error for
out-of-range values.
```

- Use the imperative mood ("Add", not "Added" or "Adds")
- First line: concise summary (50 chars or less ideal, 72 max)
- Body: explain *what* and *why*, not *how*

## What to Contribute

### Areas That Need Help

- **Feature-parity screens** — Alchemy Lab, Payload Lab, Signal Arsenal, Spectral Oracle, FapHub
- **Protobuf RPC** — a `swift-protobuf` path alongside the CLI transport (GUI/screenshot/app-bridge)
- **Hardware actions** — SubGHz/IR/NFC/RFID/iButton transmit & emulate, BadUSB
- **Multimodal** — voice (Speech framework) and camera/vision input
- **Signal format parsers** — Support for new RF/IR protocols
- **UI/UX improvements** — Animations, accessibility, responsive layouts
- **Test coverage** — Unit tests, XCUITest UI tests
- **Documentation** — Guides, tutorials

### Good First Issues

Look for issues labeled [`good first issue`](../../labels/good%20first%20issue) — these are scoped, well-documented tasks ideal for new contributors.

## Submitting Changes

1. **Ensure your code builds** without errors or warnings
2. **Test** your changes on a real device if possible
3. **Push** your branch to your fork
4. **Open a Pull Request** against the `main` branch
5. **Fill out** the PR template completely
6. **Respond** to review feedback promptly

### Pull Request Guidelines

- Keep PRs focused — one feature or fix per PR
- Include a clear description of what changed and why
- Reference related issues (e.g., "Closes #42")
- Add screenshots or recordings for UI changes
- Ensure no secrets or credentials are included

## Reporting Bugs

Use the [Bug Report](../../issues/new?template=bug_report.md) issue template. Include:

- Steps to reproduce
- Expected vs actual behavior
- Device info (iOS version, iPhone model, Flipper firmware version)
- Logs or screenshots if available

## Requesting Features

Use the [Feature Request](../../issues/new?template=feature_request.md) issue template. Describe:

- The problem you're trying to solve
- Your proposed solution
- Any alternatives you've considered

## Code of Conduct

Be respectful. We're all here to build something useful. Harassment, trolling, and unconstructive behavior won't be tolerated.

## License

By contributing, you agree that your contributions will be licensed under the [GPL-3.0 License](LICENSE).

---

Questions? Open a [Discussion](../../discussions) or reach out in an issue. We're happy to help you get started.
