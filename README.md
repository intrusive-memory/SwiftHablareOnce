# SwiftHablareOnce

ElevenLabs `HablarePlugin` for [SwiftHablare](https://github.com/intrusive-memory/SwiftHablare) 7,
backed by [SwiftOnce](https://github.com/intrusive-memory/SwiftOnce) as the HTTP client.

`ElevenLabsPlugin` (id `elevenlabs`, kind `.cloud`) provides a synthesizer and a voice designer.
Synthesis is native 24 kHz, 16-bit, mono (`pcm_24000`), returned as a WAV.

## Installation

```swift
dependencies: [
  .package(url: "https://github.com/intrusive-memory/SwiftHablareOnce.git", .upToNextMajor(from: "0.2.0")),
],
targets: [
  .target(name: "MyApp", dependencies: ["SwiftHablareOnce"]),
]
```

Requires SwiftHablare 7.1.0+ and SwiftOnce 1.1.1+ (resolved transitively).

## Usage

```swift
import SwiftHablare
import SwiftHablareOnce

let keys = KeychainAPIKeyStore()  // or any APIKeyStoring; ELEVENLABS_API_KEY is also honored
let context = PluginContext(keys: keys, registry: PluginRegistry(plugins: []))
let plugin = try await ElevenLabsPlugin(context: context)

let audio = try await plugin.synthesizer!.synthesize(
  SpeechRequest(
    text: "The harbor lights are coming on.",
    voice: .catalog(pluginId: "elevenlabs", voiceId: "<voice id>"),
    instruct: "whispering",  // sent as "[whispering] ..." on eleven_v3 and eleven_v4*
    settings: VoiceSettings(["model": .string("eleven_v4")])))
```

Design a voice and save it into a `.vox` asset:

```swift
let designer = plugin.designer(voiceName: "My Project — NARRATOR")
let candidates = try await designer.design(
  VoiceDesignRequest(description: "A calm, warm older woman", sampleText: sample))  // 100-1000 chars
var asset = VoiceAsset(name: "NARRATOR", description: "calm, warm")
try await designer.save(candidates[0], into: &asset)
// later: try await designer.delete(.catalog(pluginId: "elevenlabs", voiceId: id)) frees the slot
```

### Settings keys

Per request (`SpeechRequest.settings`): `model` (default `eleven_v4`; any `eleven_*` id),
`stability`, `similarity_boost`, `style`, `use_speaker_boost`, `speed`, `seed`.
Plugin-wide (`PluginConfiguration`): `max_concurrent_requests` (default 2). Unknown keys are rejected by name.

## Tests

- `make test` runs the offline suite, including Hablare's `ConformanceKit` against
  `ElevenLabsPlugin` with mocked HTTP and a planted key. It skips the live target.
- `make test-live` runs the live target (`SwiftHablareOnceLiveTests`). It needs `ELEVENLABS_API_KEY`
  in the environment and is skipped when it is unset or `GITHUB_ACTIONS` is `true`. It spends about
  50 characters of TTS and one voice design (3 previews), and deletes the designed voice before it returns.
  The key is passed through the environment only and is never printed.

## Requirements

- iOS 26.0+ / macOS 26.0+
- Swift 6.2+

## License

MIT. See [LICENSE](LICENSE).
