# SwiftHablareOnce — Agent Instructions

ElevenLabs `HablarePlugin` for [SwiftHablare](https://github.com/intrusive-memory/SwiftHablare) 7,
backed by [SwiftOnce](https://github.com/intrusive-memory/SwiftOnce) as the HTTP client.

## What this package is

`ElevenLabsPlugin` (id `elevenlabs`, kind `.cloud`) plus its models, settings schema, legacy
Keychain copy and quota check. The synthesizer (`ElevenLabsSynthesizer`) and designer (`ElevenLabsDesigner`) roles are in place.
Hosts register it with `PluginRegistry`. It keeps no process-wide preferences: model and voice settings
come only from request settings and `PluginConfiguration`.

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

CI uses `xcodebuild` directly on `xcode-27` runners (see `.github/workflows/tests.yml`).

## Branch Workflow

- `main` is protected (no force push, no deletion). Only PR merges land here.
- `development` is the working branch. Open PRs from feature branches into `development`,
  merge to `main` for releases.
- CI (`.github/workflows/tests.yml`) runs on PRs targeting `main`.

## Versioning

Released with `/ship-swift-library`; git tags are the source of truth for the published
version (there is no version constant in source).

This package targets `SwiftHablare >= 7.1.0` and `SwiftOnce >= 1.1.0` (both `.upToNextMajor`). Major-version bumps in
either dependency may require coordinated updates here.
