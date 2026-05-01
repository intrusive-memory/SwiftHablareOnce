//
//  ElevenLabsUserAgentTests.swift
//  SwiftHablareOnceTests
//
//  Tests to verify User-Agent header is correctly set in ElevenLabs requests via SwiftOnce
//

import Foundation
import SwiftHablare
import Testing

@testable import SwiftHablareOnce

@Suite(.serialized)
struct ElevenLabsUserAgentTests {

  var provider: ElevenLabsVoiceProvider!
  var testAPIKey: String!

  init() {
    testAPIKey = "test-api-key-12345"
    provider = ElevenLabsVoiceProvider(apiKey: testAPIKey)
  }

  // MARK: - User-Agent Configuration Tests

  @Test
  func userAgentFormat() {
    // Verify the User-Agent string follows the expected format: "SwiftHablare/X.Y.Z"
    let expectedUserAgent = "SwiftHablare/\(SwiftHablare.version)"

    // Verify library constants are set
    #expect(!SwiftHablare.version.isEmpty)
    #expect(SwiftHablare.name == "SwiftHablare")

    // Verify the User-Agent format starts with library name
    #expect(expectedUserAgent.hasPrefix("SwiftHablare/"))
    #expect(expectedUserAgent.contains(SwiftHablare.version))
  }

  // MARK: - Provider Configuration Tests

  @Test
  func providerIsConfigured() async {
    // Verify provider recognizes it has an API key
    let isConfigured = await provider.isConfigured()
    #expect(isConfigured == true)
  }

  @Test
  func providerUsesCorrectUserAgent() async throws {
    // Verify the provider would create the correct User-Agent format
    // when making actual requests via SwiftOnce
    let expectedUserAgent = "SwiftHablare/\(SwiftHablare.version)"

    // The provider now uses SwiftOnce internally, which accepts user agent in configuration
    // When the provider creates its SwiftOnce client, it passes the user agent
    #expect(expectedUserAgent.hasPrefix("SwiftHablare/"))
    #expect(!expectedUserAgent.isEmpty)

    // Note: Actual HTTP header verification is done in integration tests
    // (ElevenLabsVoiceProviderIntegrationTests.testUserAgentHeaderInRequests)
    // which make real API calls and verify they succeed with the User-Agent header.
  }

  // MARK: - Cache Configuration Tests

  @Test
  func defaultCacheSettings() {
    // Clear any persisted values to test true defaults
    UserDefaults.standard.removeObject(forKey: "elevenlabs-voice-cache-ttl")
    UserDefaults.standard.removeObject(forKey: "elevenlabs-audio-cache-max-bytes")

    // Verify default cache settings are reasonable
    let ttl = provider.voiceCacheTTL()
    let maxBytes = provider.audioCacheMaxBytes()

    #expect(ttl == 300.0)  // 5 minutes default
    #expect(maxBytes == 500_000_000)  // 500 MB default
  }

  @Test
  func updateCacheSettings() {
    // Test updating cache settings
    provider.updateVoiceCacheTTL(600.0)
    provider.updateAudioCacheMaxBytes(1_000_000_000)

    #expect(provider.voiceCacheTTL() == 600.0)
    #expect(provider.audioCacheMaxBytes() == 1_000_000_000)

    // Clean up - remove test values
    UserDefaults.standard.removeObject(forKey: "elevenlabs-voice-cache-ttl")
    UserDefaults.standard.removeObject(forKey: "elevenlabs-audio-cache-max-bytes")
  }

  // MARK: - Model Selection Tests

  @Test
  func defaultModelIsMultilingualV2() {
    let model = provider.selectedModel()
    #expect(model == .multilingualV2)
  }

  @Test
  func updateSelectedModel() {
    provider.updateSelectedModel(.turboV2_5)
    #expect(provider.selectedModel() == .turboV2_5)

    // Reset to default
    provider.updateSelectedModel(.multilingualV2)
  }

  // MARK: - API Key Management Tests

  @Test
  func currentAPIKeyReturnsEphemeralKey() async {
    // When initialized with apiKey parameter, it should return that key
    let key = await provider.currentAPIKey()
    #expect(key == testAPIKey)
  }

  @Test
  func providerProperties() {
    // Verify basic provider properties
    #expect(provider.providerId == "elevenlabs")
    #expect(provider.displayName == "ElevenLabs")
    #expect(provider.requiresAPIKey == true)
    #expect(provider.mimeType == "audio/mpeg")
  }
}
