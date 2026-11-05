//
//  ElevenLabsPluginTests.swift
//  SwiftHablareOnceTests
//
//  Sortie 9 skeleton tests. No network: SwiftOnce is driven through a mock `HTTPClient`,
//  keys through `InMemoryAPIKeyStore`, and the legacy Keychain through a counting fake.
//

import Foundation
import SwiftHablare
import SwiftHablareTesting
import SwiftOnce
import Testing

@testable import SwiftHablareOnce

private final class FakeLegacyKeychain: LegacyKeychainReading, @unchecked Sendable {
  private let lock = NSLock()
  private var reads = 0
  let key: String?
  init(key: String?) { self.key = key }
  var readCount: Int { lock.withLock { reads } }
  func legacyAPIKey() -> String? {
    lock.withLock { reads += 1 }
    return key
  }
}

private final class MockHTTP: HTTPClient, @unchecked Sendable {
  private let lock = NSLock()
  private var requests: [URLRequest] = []
  let body: Data
  init(charactersRemaining: Int) {
    let limit = 100_000
    body = Data(
      #"{"tier":"creator","status":"active","character_count":\#(limit - charactersRemaining),"character_limit":\#(limit)}"#
        .utf8)
  }
  var paths: [String] { lock.withLock { requests.compactMap { $0.url?.path } } }
  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    lock.withLock { requests.append(request) }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    return (body, response)
  }
  func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
    throw URLError(.unsupportedURL)
  }
}

private let testKey = "test-key-not-real"

private func makePlugin(
  keys: InMemoryAPIKeyStore = InMemoryAPIKeyStore(),
  legacy: FakeLegacyKeychain = FakeLegacyKeychain(key: nil),
  http: MockHTTP? = nil
) async throws -> ElevenLabsPlugin {
  let registry = PluginRegistry(plugins: [])
  return try await ElevenLabsPlugin(
    context: PluginContext(keys: keys, registry: registry),
    legacyKeychain: legacy, httpClient: http)
}

@Suite struct ElevenLabsPluginTests {

  @Test func identity() {
    #expect(ElevenLabsPlugin.id == "elevenlabs")
    #expect(ElevenLabsPlugin.kind == .cloud)
    #expect(ElevenLabsPlugin.credentials.map(\.primaryEnvironmentVariable) == ["ELEVENLABS_API_KEY"])
    #expect(
      ElevenLabsPlugin.models.map(\.id) == [
        "eleven_v4", "eleven_v4_turbo", "eleven_v3", "eleven_multilingual_v2", "eleven_flash_v2_5",
      ])
    #expect(
      ElevenLabsPlugin.settingsSchema.definition(for: "model")?.defaultValue == .string("eleven_v4"))
  }

  // MARK: Schema

  @Test func schemaRejectsUnknownKeyByName() throws {
    let settings = VoiceSettings(["stabilty": .double(0.5)])
    do {
      _ = try settings.validated(against: ElevenLabsPlugin.settingsSchema, scope: .perVoice)
      Issue.record("expected rejection")
    } catch let error as HablareError {
      #expect(String(describing: error).contains("stabilty"))
    }
  }

  @Test func schemaRejectsSpeedAboveRange() {
    #expect(throws: HablareError.self) {
      _ = try VoiceSettings(["speed": .double(1.3)])
        .validated(against: ElevenLabsPlugin.settingsSchema, scope: .perVoice)
    }
    #expect(throws: HablareError.self) {
      _ = try VoiceSettings(["speed": .double(0.69)])
        .validated(against: ElevenLabsPlugin.settingsSchema, scope: .perVoice)
    }
  }

  @Test func schemaAcceptsValidSettingsAndFillsDefaults() throws {
    let validated = try VoiceSettings([
      "speed": .double(1.2), "seed": .int(Int(UInt32.max)), "use_speaker_boost": .bool(false),
      "model": .string("eleven_v3"), "style": .int(1),
    ]).validated(against: ElevenLabsPlugin.settingsSchema, scope: .perVoice)
    #expect(validated["speed"] == .double(1.2))
    #expect(validated["style"] == .double(1))
    #expect(validated["stability"] == .double(0.5))
    #expect(validated["similarity_boost"] == .double(0.75))
    #expect(validated["seed"] == .int(Int(UInt32.max)))
  }

  @Test func schemaRejectsOutOfRangeSeedAndStability() {
    #expect(throws: HablareError.self) {
      _ = try VoiceSettings(["seed": .int(Int(UInt32.max) + 1)])
        .validated(against: ElevenLabsPlugin.settingsSchema, scope: .perVoice)
    }
    #expect(throws: HablareError.self) {
      _ = try VoiceSettings(["stability": .double(1.01)])
        .validated(against: ElevenLabsPlugin.settingsSchema, scope: .perVoice)
    }
  }

  // MARK: Status

  @Test func needsCredentialWithNoKey() async throws {
    let plugin = try await makePlugin()
    #expect(await plugin.status() == .needsCredential(envVar: "ELEVENLABS_API_KEY"))
    #expect(
      await plugin.status(estimatingCharacters: 10)
        == .needsCredential(envVar: "ELEVENLABS_API_KEY"))
  }

  @Test func readyWithKey() async throws {
    let keys = InMemoryAPIKeyStore(keys: ["elevenlabs": testKey])
    let plugin = try await makePlugin(keys: keys)
    #expect(await plugin.status() == .ready)
  }

  @Test func quotaUnavailableWhenBelowEstimateAndCached() async throws {
    let http = MockHTTP(charactersRemaining: 400)
    let keys = InMemoryAPIKeyStore(keys: ["elevenlabs": testKey])
    let plugin = try await makePlugin(keys: keys, http: http)

    // v4: 1.0 per char -> 500 > 400 remaining.
    #expect(
      await plugin.status(estimatingCharacters: 500, model: "eleven_v4")
        == .unavailable(reason: "quota"))
    // Turbo: 0.5 per char -> 250 <= 400.
    #expect(await plugin.status(estimatingCharacters: 500, model: "eleven_v4_turbo") == .ready)
    #expect(await plugin.remainingCredits() == 400)
    // Subscription fetched once for all three checks.
    #expect(http.paths == ["/v1/user/subscription"])
  }

  @Test func estimateCostUsesModelFactor() {
    #expect(ElevenLabsPlugin.estimateCost(characters: 101, model: "eleven_v4_turbo") == 51)
    #expect(ElevenLabsPlugin.estimateCost(characters: 100, model: "eleven_v3") == 100)
    #expect(ElevenLabsPlugin.estimateCost(characters: 100, model: "eleven_flash_v2_5") == 50)
  }

  // MARK: Legacy Keychain copy (OQ-5)

  @Test func legacyKeyCopiedExactlyOnce() async throws {
    let keys = InMemoryAPIKeyStore()
    let legacy = FakeLegacyKeychain(key: testKey)
    let plugin = try await makePlugin(keys: keys, legacy: legacy)

    #expect(keys.apiKey(for: "elevenlabs") == nil)
    #expect(await plugin.status() == .ready)
    #expect(keys.apiKey(for: "elevenlabs") == testKey)
    #expect(legacy.readCount == 1)

    // Later lookups find the copied key; the legacy item is not read again.
    #expect(await plugin.status() == .ready)
    #expect(legacy.readCount == 1)

    // Removing the key does not resurrect the legacy value on this instance.
    try keys.removeAPIKey(for: "elevenlabs")
    #expect(await plugin.status() == .needsCredential(envVar: "ELEVENLABS_API_KEY"))
    #expect(legacy.readCount == 1)
    #expect(keys.apiKey(for: "elevenlabs") == nil)
  }

  @Test func legacyNotReadWhenKeyAlreadyPresent() async throws {
    let keys = InMemoryAPIKeyStore(keys: ["elevenlabs": "existing"])
    let legacy = FakeLegacyKeychain(key: testKey)
    let plugin = try await makePlugin(keys: keys, legacy: legacy)
    #expect(await plugin.status() == .ready)
    #expect(legacy.readCount == 0)
    #expect(keys.apiKey(for: "elevenlabs") == "existing")
  }

  @Test func noLegacyKeyStaysNeedsCredentialAndReadsOnce() async throws {
    let legacy = FakeLegacyKeychain(key: nil)
    let plugin = try await makePlugin(legacy: legacy)
    _ = await plugin.status()
    _ = await plugin.status()
    #expect(legacy.readCount == 1)
  }
}
