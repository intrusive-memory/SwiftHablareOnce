# SwiftHablareOnce

ElevenLabs `VoiceProvider` for [SwiftHablare](https://github.com/intrusive-memory/SwiftHablare),
backed by [SwiftOnce](https://github.com/intrusive-memory/SwiftOnce) as the HTTP client.

This package was extracted from SwiftHablare core in 6.0 so the host library could stay
provider-agnostic. SwiftHablare itself ships only the on-device `AppleVoiceProvider`; cloud
providers like ElevenLabs are added by depending on this package.

## Installation

```swift
dependencies: [
  .package(url: "https://github.com/intrusive-memory/SwiftHablareOnce.git", .upToNextMajor(from: "0.1.0")),
],
targets: [
  .target(name: "MyApp", dependencies: ["SwiftHablareOnce"]),
]
```

Requires SwiftHablare 6.3.0+ and SwiftOnce 1.0.0+ (resolved transitively).

## Usage

Register the descriptor with SwiftHablare's registry at app/launch time:

```swift
import SwiftHablare
import SwiftHablareOnce

await VoiceProviderRegistry.shared.register(ElevenLabsVoiceProvider.descriptor)
```

The provider is disabled by default and requires an API key. Configuration UI is provided
through SwiftHablare's `configurationPanel(for:onConfigured:)` API on macOS / iOS targets
that import SwiftUI.

## Requirements

- iOS 26.0+ / macOS 26.0+
- Swift 6.2+, Xcode 26+

## License

MIT. See [LICENSE](LICENSE).
