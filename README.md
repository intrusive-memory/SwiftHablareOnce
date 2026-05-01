# SwiftHablareOnce

ElevenLabs `VoiceProvider` for [SwiftHablare](https://github.com/intrusive-memory/SwiftHablare),
backed by [SwiftOnce](https://github.com/intrusive-memory/SwiftOnce) as the HTTP client.

This package was extracted from SwiftHablare core in 6.0 so the host library could stay
provider-agnostic. SwiftHablare itself ships only the on-device `AppleVoiceProvider`; cloud
providers like ElevenLabs are added by depending on this package.

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

## Platforms

- iOS 26.0+
- macOS 26.0+

## License

Same as SwiftHablare.
