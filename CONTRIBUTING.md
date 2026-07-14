# Contributing to YomiKit

Thanks for your interest in improving YomiKit. This document explains how to get a working development setup and what we expect from pull requests.

## Development setup

YomiKit is a plain Swift package with zero third-party dependencies. Any Swift 6 toolchain works:

```bash
git clone https://github.com/JaydenCJ/yomikit.git
cd yomikit

# macOS 13+ with Xcode 16, or a Linux machine with Swift 6 installed
swift build
swift test

# no local toolchain? use Docker
docker run --rm -v "$PWD:/src" -w /src swift:6.0.3 swift test

# quick offline sanity checks
bash scripts/smoke.sh
```

The Apple layer (`Sources/YomiKit`) only compiles on Apple platforms; everything else, including the whole test suite for the core, runs on Linux.

## Project layout

| Path | What lives there |
|---|---|
| `Sources/YomiKitCore` | Platform-independent logic: geometry, layout analysis, table reconstruction, receipt extraction, text normalization, export, the `OCRBackend` abstraction |
| `Sources/YomiKit` | Apple layer: Vision / Core ML backends, `YomiScanner` (all behind `#if canImport(...)`) |
| `Tests/` | XCTest suites; everything is runnable on Linux |
| `tools/` | Python scripts to convert or distill custom recognition models |
| `scripts/smoke.sh` | Offline smoke checks |

## Ground rules

- **Keep the core platform-independent.** Nothing under `Sources/YomiKitCore` may import an Apple-only framework. New inference engines go behind the `OCRBackend` protocol.
- **No model weights in the repo.** Ever. Conversion scripts must accept user-provided checkpoints and must not download anything.
- **Tests accompany logic.** New extraction rules, layout heuristics or parsers need unit tests with realistic Japanese fixtures (see `Tests/YomiKitCoreTests/Fixtures.swift`).
- **Comments and identifiers are English.** Japanese belongs in test fixtures and documentation translations.
- **Run `swift test` and `bash scripts/smoke.sh` before opening a PR.**

## Pull requests

1. Fork, create a feature branch, keep the change focused.
2. Add or update tests that demonstrate the change.
3. Update the three READMEs together if user-facing behavior changes (`README.md` is authoritative; `README.zh.md` and `README.ja.md` must stay in sync).
4. Describe in the PR what real-world input (receipt style, layout pattern) motivated the change.

## Reporting issues

Please include a minimal reproduction: the `TextObservation` list (or text lines) that produced the wrong result and the output you expected. That is usually enough to turn a report into a regression test.
