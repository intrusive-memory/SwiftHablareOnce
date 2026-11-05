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
make test     # offline xcodebuild test (skips the live target)
make test-live # gated live ElevenLabs tests (needs ELEVENLABS_API_KEY)
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

This package targets `SwiftHablare >= 7.1.0` and `SwiftOnce >= 1.1.1` (both `.upToNextMajor`). Major-version bumps in
either dependency may require coordinated updates here.

## Tests and live-test observations

- `ElevenLabsConformanceTests` runs `ConformanceKit.run(ElevenLabsPlugin.self, ...)` in `make test`. The kit
  builds the plugin itself, so HTTP is mocked with a `URLProtocol` on `URLSession.shared`.
- `SwiftHablareOnceLiveTests` is a separate target. `make test` and CI pass `-skip-testing:SwiftHablareOnceLiveTests`;
  the tests also self-gate on `ELEVENLABS_API_KEY` and `GITHUB_ACTIONS != "true"`. Run `make test-live` (once; it spends
  real credits). Never print the key.
- Observed 2026-11-04 (settles recon X-02): `eleven_v4` accepts `[whispering]`-style instruct (HTTP 200, 24 kHz mono
  16-bit WAV, `droppedInstruct == false`). Whether the tag is spoken aloud was not transcribed.
- Observed 2026-11-04: the design API returns previews with media type `audio/pcm` when `pcm_24000` is requested (3 previews).
- A designed voice is deleted in the test's cleanup; `voice_slots_used` was 4 before and 4 after.

## Development cycle

Current cycle: 0.2.0-dev (post-v0.2.0; the next release version is chosen at ship time).
