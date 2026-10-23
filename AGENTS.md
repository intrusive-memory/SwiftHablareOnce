# SwiftHablareOnce — Agent Instructions

ElevenLabs `VoiceProvider` for [SwiftHablare](https://github.com/intrusive-memory/SwiftHablare),
backed by [SwiftOnce](https://github.com/intrusive-memory/SwiftOnce) as the HTTP client.

## What this package is

A thin extension package. SwiftHablare core ships only the on-device `AppleVoiceProvider`;
this package adds an `ElevenLabsVoiceProvider` implementation that depends on SwiftOnce for
its HTTP layer. Consumers register the descriptor at app launch:

```swift
import SwiftHablare
import SwiftHablareOnce

await VoiceProviderRegistry.shared.register(ElevenLabsVoiceProvider.descriptor)
```

## Platforms

- iOS 26.0+
- macOS 26.0+
- Swift 6.2+

## Build & Test

This is a **Makefile-first project**. Use `make` targets, never `swift build`/`swift test`.

```bash
make help     # list targets
make build    # xcodebuild build of the library
make test     # xcodebuild test
make lint     # swift format -i -r .
make resolve  # resolve SPM dependencies
make clean    # remove DerivedData artifacts
```

CI uses `xcodebuild` directly on `macos-26` runners (see `.github/workflows/tests.yml`).

## Sibling Dependency Pattern

During a development cycle, `Package.swift` uses a sibling-checkout override: when
`../SwiftHablare` (or `../SwiftOnce`) exists on disk and `CI` is unset, the package resolves
against the local path; otherwise it falls back to the pinned remote release. Tagged releases
ship a remote-only `Package.swift` (no `sibling(...)` helper); `/branch-hygiene` restores the
helper on `development` after each release.

## Branch Workflow

- `main` is protected (no force push, no deletion). Only PR merges land here.
- `development` is the working branch. Open PRs from feature branches into `development`,
  merge to `main` for releases.
- CI (`.github/workflows/tests.yml`) runs on PRs targeting `main`.

## Type Aliasing Note

Both `SwiftHablare` and `SwiftOnce` export a public `Voice` type. The two cannot be imported
together with bare `Voice` references (the `SwiftHablare` namespace struct also shadows the
module name, blocking `SwiftHablare.Voice` qualification). `HablareAliases.swift` defines a
public `HablareVoice = Voice` typealias — declared in a file that imports only SwiftHablare,
where the symbol is unambiguous. Use `HablareVoice` anywhere both modules are imported.

## Versioning

Released with `/ship-swift-library`; git tags are the source of truth for the published
version (there is no version constant in source).

This package targets `SwiftHablare >= 6.3.0` and `SwiftOnce >= 1.0.0` (both `.upToNextMajor`). Major-version bumps in
either dependency may require coordinated updates here.
