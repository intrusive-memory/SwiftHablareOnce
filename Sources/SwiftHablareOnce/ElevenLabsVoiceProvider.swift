//
//  ElevenLabsVoiceProvider.swift
//  SwiftHablareOnce
//
//  ElevenLabs implementation of VoiceProvider using SwiftOnce
//

import Foundation
import SwiftHablare
import SwiftOnce

#if canImport(SwiftUI)
  import SwiftUI
#endif

/// ElevenLabs TTS model options
public enum ElevenLabsModel: String, CaseIterable, Identifiable {
  /// Latest multilingual model (v2) - Highest quality, emotionally-aware, 29 languages
  case multilingualV2 = "eleven_multilingual_v2"

  /// Turbo model (v2.5) - Fastest, optimized for low latency
  case turboV2_5 = "eleven_turbo_v2_5"

  /// Turbo model (v2) - Fast, lower latency
  case turboV2 = "eleven_turbo_v2"

  /// First multilingual model (v1) - Legacy, supports multiple languages
  case multilingualV1 = "eleven_multilingual_v1"

  /// Original English-only model (v1) - Legacy, English only
  case monolingualV1 = "eleven_monolingual_v1"

  public var id: String { rawValue }

  /// Display name for the model
  public var displayName: String {
    switch self {
    case .multilingualV2:
      return "Multilingual v2 (Highest Quality)"
    case .turboV2_5:
      return "Turbo v2.5 (Fastest)"
    case .turboV2:
      return "Turbo v2 (Fast)"
    case .multilingualV1:
      return "Multilingual v1 (Legacy)"
    case .monolingualV1:
      return "Monolingual v1 (English Only, Legacy)"
    }
  }

  /// Description of the model's capabilities
  public var description: String {
    switch self {
    case .multilingualV2:
      return
        "Latest model with highest quality, emotionally-aware output, supports 29 languages. Best for production use."
    case .turboV2_5:
      return "Fastest model with optimized latency. Good balance of quality and speed."
    case .turboV2:
      return "Fast model with lower latency. Good for real-time applications."
    case .multilingualV1:
      return
        "First-generation multilingual model. Supports multiple languages but lower quality than v2."
    case .monolingualV1:
      return "Original English-only model. Legacy support only."
    }
  }

  /// Default model (highest quality)
  public static var `default`: ElevenLabsModel {
    .multilingualV2
  }
}

// Thread-safe wrapper for SwiftOnce actor reference
private final class SwiftOnceClientBox: @unchecked Sendable {
  private let lock = NSLock()
  private var _client: SwiftOnce?

  var client: SwiftOnce? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return _client
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      _client = newValue
    }
  }
}

/// ElevenLabs implementation of VoiceProvider using SwiftOnce
public final class ElevenLabsVoiceProvider: VoiceProvider {
  public let providerId = "elevenlabs"
  public let displayName = "ElevenLabs"
  public let requiresAPIKey = true
  public let mimeType = "audio/mpeg"  // MP3 format from API
  public var defaultVoiceId: String? { ElevenLabsDefaults.defaultVoiceId }

  private let keychainManager: KeychainManagerProtocol
  private let apiKeyAccount = "elevenlabs-api-key"
  private let ephemeralAPIKey: String?

  // SwiftOnce client (created lazily when API key is available)
  // Stored in a thread-safe box since SwiftOnce is an actor
  private let clientBox = SwiftOnceClientBox()

  private var swiftOnceClient: SwiftOnce? {
    get { clientBox.client }
    set { clientBox.client = newValue }
  }

  /// Initialize with optional keychain manager and API key
  /// - Parameters:
  ///   - keychainManager: Keychain manager to use (defaults to shared singleton)
  ///   - apiKey: Optional API key to use instead of keychain (primarily for testing)
  public init(
    keychainManager: KeychainManagerProtocol = KeychainManager.shared, apiKey: String? = nil
  ) {
    self.keychainManager = keychainManager
    self.ephemeralAPIKey = apiKey
  }

  /// User-Agent string for HTTP requests
  private var userAgent: String {
    "\(SwiftHablare.name)/\(SwiftHablare.version)"
  }

  /// Get or create SwiftOnce client with API key
  private func client() async throws -> SwiftOnce {
    // Return cached client if available
    if let client = swiftOnceClient {
      return client
    }

    // Get API key
    let apiKey = try await getAPIKey()

    // Create configuration with user settings
    let selectedModel = self.selectedModel().toSwiftOnceModel()
    let config = SwiftOnceConfiguration(
      userAgent: userAgent,
      voiceCacheTTL: voiceCacheTTL(),
      audioCacheMaxBytes: audioCacheMaxBytes(),
      defaultModel: selectedModel,
      defaultOutputFormat: .mp3_44100_128  // Match current behavior
    )

    // Create and cache client
    let client = SwiftOnce(apiKey: apiKey, configuration: config)
    self.swiftOnceClient = client
    return client
  }

  /// Get API key from ephemeral storage (test) or keychain (production)
  private func getAPIKey() async throws -> String {
    if let ephemeralKey = ephemeralAPIKey {
      return ephemeralKey
    }
    return try await keychainManager.getAPIKey(for: apiKeyAccount)
  }

  // MARK: - VoiceProvider Protocol

  public func isConfigured() async -> Bool {
    do {
      _ = try await getAPIKey()
      return true
    } catch {
      return false
    }
  }

  public func fetchVoices(languageCode: String) async throws -> [HablareVoice] {
    let client = try await client()

    // Fetch all voices from SwiftOnce
    let response = try await client.voices()

    // Filter by language if needed and convert to Hablare Voice model
    let filtered = response.voices.filter { voice in
      // If no verified languages, include the voice
      guard let verifiedLanguages = voice.verifiedLanguages else {
        return true
      }

      // Check if any verified language matches the requested language code
      return verifiedLanguages.contains { verifiedLang in
        if let locale = verifiedLang.locale {
          return locale.lowercased().hasPrefix(languageCode.lowercased())
        }
        if let language = verifiedLang.language {
          return language.lowercased().hasPrefix(languageCode.lowercased())
        }
        return false
      }
    }

    return filtered.map { convertToHablareVoice($0) }
  }

  public func generateAudio(text: String, voiceId: String, languageCode: String) async throws
    -> Data
  {
    let client = try await client()

    // Generate audio using SwiftOnce
    return try await client.speak(
      text,
      voice: voiceId,
      languageCode: languageCode
    )
  }

  public func estimateDuration(text: String, voiceId: String) async -> TimeInterval {
    // Heuristic estimation: ~150 words per minute for English
    // Roughly 2.5 words per second, or 0.4 seconds per word
    let words = text.split(separator: " ").count
    return Double(words) * 0.4
  }

  public func isVoiceAvailable(voiceId: String) async -> Bool {
    do {
      let client = try await client()
      _ = try await client.voice(voiceId)
      return true
    } catch {
      return false
    }
  }

  // MARK: - API Key Management

  /// Retrieve the current API key if one exists.
  public func currentAPIKey() async -> String? {
    if let ephemeralAPIKey {
      return ephemeralAPIKey
    }
    return try? await keychainManager.getAPIKey(for: apiKeyAccount)
  }

  /// Persist a new API key for ElevenLabs usage.
  public func updateAPIKey(_ apiKey: String) async throws {
    guard ephemeralAPIKey == nil else {
      return
    }
    try await keychainManager.saveAPIKey(apiKey, for: apiKeyAccount)
    // Invalidate cached client so new key is used
    swiftOnceClient = nil
  }

  /// Remove the stored API key from secure storage.
  public func clearAPIKey() async throws {
    guard ephemeralAPIKey == nil else {
      return
    }
    try await keychainManager.deleteAPIKey(for: apiKeyAccount)
    // Invalidate cached client
    swiftOnceClient = nil
  }

  // MARK: - Model Selection

  /// Get the currently selected ElevenLabs model
  public func selectedModel() -> ElevenLabsModel {
    guard let modelString = UserDefaults.standard.string(forKey: "elevenlabs-selected-model"),
      let model = ElevenLabsModel(rawValue: modelString)
    else {
      return .default
    }
    return model
  }

  /// Update the selected ElevenLabs model
  public func updateSelectedModel(_ model: ElevenLabsModel) {
    UserDefaults.standard.set(model.rawValue, forKey: "elevenlabs-selected-model")
    // Invalidate cached client so new model is used
    swiftOnceClient = nil
  }

  // MARK: - Cache Configuration

  /// Get voice cache TTL (time-to-live) in seconds
  public func voiceCacheTTL() -> TimeInterval {
    // Default: 5 minutes (300 seconds)
    return UserDefaults.standard.double(forKey: "elevenlabs-voice-cache-ttl").nonZero ?? 300.0
  }

  /// Update voice cache TTL
  public func updateVoiceCacheTTL(_ ttl: TimeInterval) {
    UserDefaults.standard.set(ttl, forKey: "elevenlabs-voice-cache-ttl")
    // Invalidate cached client so new TTL is used
    swiftOnceClient = nil
  }

  /// Get audio cache max size in bytes
  public func audioCacheMaxBytes() -> Int64 {
    // Default: 500 MB
    let defaultSize: Int64 = 500_000_000
    let stored = UserDefaults.standard.object(forKey: "elevenlabs-audio-cache-max-bytes") as? Int64
    return stored ?? defaultSize
  }

  /// Update audio cache max size in bytes
  public func updateAudioCacheMaxBytes(_ bytes: Int64) {
    UserDefaults.standard.set(bytes, forKey: "elevenlabs-audio-cache-max-bytes")
    // Invalidate cached client so new cache size is used
    swiftOnceClient = nil
  }

  /// Clear audio cache
  public func clearAudioCache() async throws {
    guard let client = swiftOnceClient else {
      return
    }
    try await client.clearAudioCache()
  }

  /// Get current audio cache size
  public func audioCacheSize() async throws -> Int64 {
    guard let client = swiftOnceClient else {
      return 0
    }
    return try await client.audioCacheSize()
  }

  /// Invalidate voice cache
  public func invalidateVoiceCache() async {
    guard let client = swiftOnceClient else {
      return
    }
    await client.invalidateVoiceCache()
  }

  #if canImport(SwiftUI)
    @MainActor
    public func makeConfigurationView(onConfigured: @escaping (Bool) -> Void) -> AnyView {
      AnyView(ElevenLabsVoiceProviderConfigurationView(provider: self, onConfigured: onConfigured))
    }
  #endif
}

// MARK: - SwiftUI Configuration View

#if canImport(SwiftUI)
  @MainActor
  private struct ElevenLabsVoiceProviderConfigurationView: View {
    @State private var apiKey: String = ""
    @State private var selectedModel: ElevenLabsModel
    @State private var voiceCacheTTL: Double
    @State private var audioCacheMaxMB: Double
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var hasAPIKey = false

    let provider: ElevenLabsVoiceProvider
    let onConfigured: (Bool) -> Void

    init(provider: ElevenLabsVoiceProvider, onConfigured: @escaping (Bool) -> Void) {
      self.provider = provider
      self.onConfigured = onConfigured
      _selectedModel = State(initialValue: provider.selectedModel())
      _voiceCacheTTL = State(initialValue: provider.voiceCacheTTL())
      _audioCacheMaxMB = State(initialValue: Double(provider.audioCacheMaxBytes()) / 1_000_000)
    }

    var body: some View {
      Form {
        Section(header: Text("API Key")) {
          SecureField("Enter ElevenLabs API Key", text: $apiKey)
            .textContentType(.password)
            .disabled(isProcessing)

          if let errorMessage {
            Text(errorMessage)
              .font(.footnote)
              .foregroundStyle(.red)
          }
        }

        Section {
          Picker("Model", selection: $selectedModel) {
            ForEach(ElevenLabsModel.allCases) { model in
              VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                  .font(.body)
                Text(model.description)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              .tag(model)
            }
          }
          .onChange(of: selectedModel) { _, newModel in
            provider.updateSelectedModel(newModel)
          }

          Link(destination: URL(string: "https://elevenlabs.io/docs/speech-synthesis/models")!) {
            Label("View Model Documentation", systemImage: "book.fill")
          }
        } header: {
          Text("Voice Model")
        } footer: {
          Text(selectedModel.description)
            .font(.footnote)
        }

        Section {
          VStack(alignment: .leading, spacing: 8) {
            Text("Voice Cache TTL: \(Int(voiceCacheTTL))s")
              .font(.subheadline)
            Slider(value: $voiceCacheTTL, in: 60...3600, step: 60)
              .onChange(of: voiceCacheTTL) { _, newValue in
                provider.updateVoiceCacheTTL(newValue)
              }
          }

          VStack(alignment: .leading, spacing: 8) {
            Text("Audio Cache Max: \(Int(audioCacheMaxMB)) MB")
              .font(.subheadline)
            Slider(value: $audioCacheMaxMB, in: 100...2000, step: 100)
              .onChange(of: audioCacheMaxMB) { _, newValue in
                provider.updateAudioCacheMaxBytes(Int64(newValue * 1_000_000))
              }
          }

          Button {
            clearCaches()
          } label: {
            Label("Clear Caches", systemImage: "trash")
          }
        } header: {
          Text("Cache Settings")
        } footer: {
          Text(
            "Voice cache stores voice lists temporarily. Audio cache stores generated audio files."
          )
          .font(.footnote)
        }

        Section {
          Button {
            saveAPIKey()
          } label: {
            if isProcessing {
              ProgressView()
            } else {
              Text("Save API Key")
            }
          }
          .disabled(apiKey.isEmpty || isProcessing)

          Button(role: .destructive) {
            removeAPIKey()
          } label: {
            Text("Remove API Key")
          }
          .disabled(isProcessing || !hasAPIKey)
        }
      }
      .navigationTitle(provider.displayName)
      .task {
        // Load current API key on appear
        if let currentKey = await provider.currentAPIKey() {
          apiKey = currentKey
          hasAPIKey = true
        }
      }
    }

    private func saveAPIKey() {
      guard !apiKey.isEmpty else { return }
      isProcessing = true
      errorMessage = nil

      Task { @MainActor in
        do {
          try await provider.updateAPIKey(apiKey)
          hasAPIKey = true
          onConfigured(true)
        } catch {
          errorMessage = error.localizedDescription
          onConfigured(false)
        }

        isProcessing = false
      }
    }

    private func removeAPIKey() {
      isProcessing = true
      errorMessage = nil

      Task { @MainActor in
        do {
          try await provider.clearAPIKey()
          apiKey = ""
          hasAPIKey = false
          onConfigured(false)
        } catch {
          errorMessage = error.localizedDescription
        }

        isProcessing = false
      }
    }

    private func clearCaches() {
      Task {
        do {
          try await provider.clearAudioCache()
          await provider.invalidateVoiceCache()
        } catch {
          errorMessage = error.localizedDescription
        }
      }
    }
  }
#endif

// MARK: - Provider Descriptor

extension ElevenLabsVoiceProvider {
  public static var descriptor: VoiceProviderDescriptor {
    VoiceProviderDescriptor(
      id: "elevenlabs",
      displayName: "ElevenLabs",
      isEnabledByDefault: false,
      requiresConfiguration: true,
      makeProvider: { ElevenLabsVoiceProvider() }
    )
  }
}

// MARK: - Helpers

extension Double {
  fileprivate var nonZero: Double? {
    self > 0 ? self : nil
  }
}
