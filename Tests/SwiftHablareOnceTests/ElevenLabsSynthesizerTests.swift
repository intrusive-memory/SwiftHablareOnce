//
//  ElevenLabsSynthesizerTests.swift
//  SwiftHablareOnceTests
//
//  Sortie 10. No network: SwiftOnce is driven through a path-routing mock `HTTPClient`.
//

import Foundation
import SwiftHablare
import SwiftHablareTesting
import SwiftOnce
import Testing

@testable import SwiftHablareOnce

private let key = "sk_test_key_not_real_123"

private struct Reply {
  var status = 200
  var body = Data()
  var headers: [String: String] = [:]
}

private final class RoutingHTTP: HTTPClient, @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [URLRequest] = []
  let remaining: Int
  var tts: Reply
  init(remaining: Int = 100_000, tts: Reply) {
    self.remaining = remaining
    self.tts = tts
  }

  var ttsRequests: [URLRequest] {
    lock.withLock { recorded.filter { $0.url?.path.hasPrefix("/v1/text-to-speech/") == true } }
  }
  var allPaths: [String] { lock.withLock { recorded.compactMap { $0.url?.path } } }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    lock.withLock { recorded.append(request) }
    let reply: Reply
    if request.url?.path == "/v1/user/subscription" {
      reply = Reply(
        body: Data(
          #"{"tier":"creator","status":"active","character_count":\#(100_000 - remaining),"character_limit":100000}"#
            .utf8))
    } else {
      reply = tts
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
    return (reply.body, response)
  }
  func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
    throw URLError(.unsupportedURL)
  }
}

private struct NoLegacy: LegacyKeychainReading {
  func legacyAPIKey() -> String? { nil }
}

/// 100 samples of 16-bit PCM = 200 bytes.
private let pcm = Data((0..<200).map { UInt8($0 % 251) })

private func okReply() -> Reply { Reply(status: 200, body: pcm, headers: ["request-id": "r1"]) }

private func makeSynth(
  http: RoutingHTTP, configuration: PluginConfiguration = .empty, maxRetries: Int = 0
) async throws -> ElevenLabsSynthesizer {
  let context = PluginContext(
    keys: InMemoryAPIKeyStore(keys: ["elevenlabs": key]), configuration: configuration,
    registry: PluginRegistry(plugins: []))
  let plugin = try await ElevenLabsPlugin(
    context: context, legacyKeychain: NoLegacy(), httpClient: http,
    onceConfiguration: SwiftOnceConfiguration(
      defaultModel: Model("eleven_v4"), maxRetries: maxRetries))
  return try #require(plugin.synthesizer as? ElevenLabsSynthesizer)
}

private func request(
  _ text: String = "Hello there.", model: String? = nil, instruct: String? = nil,
  extra: [String: SettingValue] = [:], previous: String? = nil, next: String? = nil,
  voice: VoiceReference = .catalog(pluginId: "elevenlabs", voiceId: "voice123")
) -> SpeechRequest {
  var values = extra
  if let model { values["model"] = .string(model) }
  return SpeechRequest(
    text: text, voice: voice, instruct: instruct, settings: VoiceSettings(values),
    previousText: previous, nextText: next)
}

private func body(_ req: URLRequest) throws -> [String: Any] {
  let data = try #require(req.httpBody)
  let object = try JSONSerialization.jsonObject(with: data)
  return try #require(object as? [String: Any])
}

@Suite struct ElevenLabsSynthesizerTests {

  @Test func pcm24kIsWrappedInA44ByteWavHeader() async throws {
    let http = RoutingHTTP(tts: okReply())
    let synth = try await makeSynth(http: http)
    let audio = try await synth.synthesize(request())

    let sent = try #require(http.ttsRequests.first)
    #expect(sent.url?.query?.contains("output_format=pcm_24000") == true)
    #expect(sent.url?.path == "/v1/text-to-speech/voice123")

    let d = audio.data
    #expect(d.count == 44 + pcm.count)
    #expect(String(decoding: d[0..<4], as: UTF8.self) == "RIFF")
    #expect(String(decoding: d[8..<16], as: UTF8.self) == "WAVEfmt ")
    func u32(_ at: Int) -> UInt32 { d[at..<at + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) } }
    func u16(_ at: Int) -> UInt16 { UInt16(d[at]) | UInt16(d[at + 1]) << 8 }
    #expect(u32(4) == UInt32(36 + pcm.count))
    #expect(u16(20) == 1)  // PCM
    #expect(u16(22) == 1)  // mono
    #expect(u32(24) == 24_000)
    #expect(u32(28) == 48_000)
    #expect(u16(32) == 2)
    #expect(u16(34) == 16)
    #expect(String(decoding: d[36..<40], as: UTF8.self) == "data")
    #expect(u32(40) == UInt32(pcm.count))
    #expect(d.dropFirst(44) == pcm)

    #expect(audio.format == AudioFormat(container: .wav, sampleRate: 24_000, channels: 1, bitDepth: 16))
    #expect(abs(audio.duration - 100.0 / 24_000) < 1e-9)
    #expect(synth.nativeFormats.contains(.pcm24kMono16))
  }

  @Test func instructMappedOnV4() async throws {
    let http = RoutingHTTP(tts: okReply())
    let synth = try await makeSynth(http: http)
    let audio = try await synth.synthesize(
      request("Hi.", model: "eleven_v4", instruct: "(whispering)"))
    #expect(audio.droppedInstruct == false)
    let json = try body(try #require(http.ttsRequests.first))
    #expect(json["text"] as? String == "[whispering] Hi.")
    #expect(json["model_id"] as? String == "eleven_v4")
    #expect(synth.capabilities(forModel: "eleven_v4").contains(.instruct))
    #expect(synth.capabilities(forModel: "eleven_v3").contains(.instruct))
    #expect(!synth.capabilities(forModel: "eleven_multilingual_v2").contains(.instruct))
  }

  @Test func instructDroppedOnMultilingualV2() async throws {
    let http = RoutingHTTP(tts: okReply())
    let synth = try await makeSynth(http: http)
    let audio = try await synth.synthesize(
      request("Hi.", model: "eleven_multilingual_v2", instruct: "(whispering)"))
    #expect(audio.droppedInstruct == true)
    let json = try body(try #require(http.ttsRequests.first))
    #expect(json["text"] as? String == "Hi.")
  }

  @Test func noInstructMeansNotDropped() async throws {
    let http = RoutingHTTP(tts: okReply())
    let synth = try await makeSynth(http: http)
    let audio = try await synth.synthesize(request(model: "eleven_multilingual_v2", instruct: "  "))
    #expect(audio.droppedInstruct == false)
  }

  @Test func previousAndNextTextAreSent() async throws {
    let http = RoutingHTTP(tts: okReply())
    let synth = try await makeSynth(http: http)
    _ = try await synth.synthesize(request(previous: "Before.", next: "After."))
    let json = try body(try #require(http.ttsRequests.first))
    #expect(json["previous_text"] as? String == "Before.")
    #expect(json["next_text"] as? String == "After.")
  }

  @Test func voiceSettingsAndSeedAreSent() async throws {
    let http = RoutingHTTP(tts: okReply())
    let synth = try await makeSynth(http: http)
    _ = try await synth.synthesize(
      request(extra: ["stability": .double(0.2), "speed": .double(1.1), "seed": .int(7)]))
    let json = try body(try #require(http.ttsRequests.first))
    let vs = try #require(json["voice_settings"] as? [String: Any])
    #expect(vs["stability"] as? Double == 0.2)
    #expect(vs["speed"] as? Double == 1.1)
    #expect(json["seed"] as? Int == 7)
  }

  // MARK: Model passthrough (EL-1.3)

  @Test func passthroughModelIdIsAcceptedWithConservativeFacts() async throws {
    let http = RoutingHTTP(tts: okReply())
    let synth = try await makeSynth(http: http)
    _ = try await synth.synthesize(
      request("Hi.", model: "eleven_v9_future", instruct: "(whispering)"))
    let json = try body(try #require(http.ttsRequests.first))
    #expect(json["model_id"] as? String == "eleven_v9_future")
    #expect(json["text"] as? String == "Hi.")  // no instruct on an unknown model
    #expect(synth.limits(forModel: "eleven_v9_future").maxCharacters == 5000)
    #expect(ElevenLabsPlugin.estimateCost(characters: 10, model: "eleven_v9_future") == 10)
    #expect(!synth.capabilities(forModel: "eleven_v9_future").contains(.instruct))
    #expect(ElevenLabsPlugin.models.count == 5)
  }

  @Test func invalidModelIdsAreRejected() async throws {
    let http = RoutingHTTP(tts: okReply())
    let synth = try await makeSynth(http: http)
    for bad in ["gpt-4", "eleven_", "Eleven_V4", "eleven_v4;drop", "eleven v4", "eleven_v4\n", ""] {
      await #expect(throws: HablareError.self, "\(bad.debugDescription)") {
        _ = try await synth.synthesize(request(model: bad))
      }
    }
    #expect(http.ttsRequests.isEmpty)
    #expect(ElevenLabsModels.isValidModelId("eleven_v4_turbo"))
  }

  @Test func perModelLimitIsEnforced() async throws {
    let http = RoutingHTTP(tts: okReply())
    let synth = try await makeSynth(http: http)
    #expect(synth.limits.maxCharacters == 10_000)
    #expect(synth.limits(forModel: "eleven_v3").maxCharacters == 5_000)
    #expect(synth.limits(forModel: "eleven_flash_v2_5").maxCharacters == 40_000)
    await #expect(throws: HablareError.self) {
      _ = try await synth.synthesize(request(String(repeating: "a", count: 5_001), model: "eleven_v3"))
    }
    #expect(http.ttsRequests.isEmpty)
  }

  // MARK: Cost, quota, concurrency

  @Test func estimateCostIsCharsTimesFactor() async throws {
    let synth = try await makeSynth(http: RoutingHTTP(tts: okReply()))
    let turbo = synth.estimateCost(request(String(repeating: "a", count: 101), model: "eleven_v4_turbo"))
    #expect(turbo?.quantity == 51)
    #expect(turbo?.unit == .credits)
    #expect(synth.estimateCost(request("abcd", model: "eleven_v3"))?.quantity == 4)
  }

  @Test func insufficientQuotaThrowsPermanentErrorBeforeSynthesis() async throws {
    let http = RoutingHTTP(remaining: 5, tts: okReply())
    let synth = try await makeSynth(http: http)
    do {
      _ = try await synth.synthesize(request("This line is longer than five credits."))
      Issue.record("expected quota error")
    } catch let error as HablareError {
      guard case .quotaExceeded = error else {
        Issue.record("wrong error \(error)")
        return
      }
      #expect(error.category == .permanent)
      #expect(String(describing: error).lowercased().contains("quota"))
    }
    #expect(http.ttsRequests.isEmpty)
  }

  @Test func quotaExceededFromServerIsPermanent() async throws {
    let reply = Reply(
      status: 401, body: Data(#"{"detail":{"status":"quota_exceeded","message":"out"}}"#.utf8))
    let synth = try await makeSynth(http: RoutingHTTP(tts: reply))
    do {
      _ = try await synth.synthesize(request())
      Issue.record("expected error")
    } catch let error as HablareError {
      guard case .quotaExceeded = error else {
        Issue.record("wrong error \(error)")
        return
      }
    }
  }

  @Test func concurrencyDefaultsToTwoAndIsConfigurable() async throws {
    let http = RoutingHTTP(tts: okReply())
    #expect(try await makeSynth(http: http).maxConcurrentRequests == 2)
    let configured = try await makeSynth(
      http: http, configuration: PluginConfiguration(settings: ["max_concurrent_requests": .int(5)]))
    #expect(configured.maxConcurrentRequests == 5)
  }

  // MARK: Errors

  @Test func unauthorizedIsPermanentAndNeverShowsTheKey() async throws {
    let reply = Reply(status: 401, body: Data(#"{"detail":{"message":"bad key \#(key)"}}"#.utf8))
    let synth = try await makeSynth(http: RoutingHTTP(tts: reply))
    do {
      _ = try await synth.synthesize(request())
      Issue.record("expected error")
    } catch let error as HablareError {
      #expect(error.category == .permanent)
      let text = String(describing: error) + "\(error)" + String(reflecting: error)
      #expect(!text.contains(key))
      #expect(text.contains("key rejected"))
    }
  }

  @Test func serverErrorAndRateLimitAreTransientAndKeyFree() async throws {
    for status in [429, 503] {
      let reply = Reply(status: status, body: Data("oops \(key)".utf8))
      let synth = try await makeSynth(http: RoutingHTTP(tts: reply), maxRetries: 0)
      do {
        _ = try await synth.synthesize(request())
        Issue.record("expected error")
      } catch let error as HablareError {
        #expect(error.category == .transient)
        #expect(!String(reflecting: error).contains(key))
        #expect(!String(describing: error).contains(key))
      }
    }
  }

  @Test func retriesServerErrorsViaSwiftOnce() async throws {
    // maxRetries 1 with a persistent 503: SwiftOnce makes two attempts.
    let http = RoutingHTTP(tts: Reply(status: 503, headers: ["Retry-After": "0"]))
    let synth = try await makeSynth(http: http, maxRetries: 1)
    await #expect(throws: HablareError.self) { _ = try await synth.synthesize(request()) }
    #expect(http.ttsRequests.count == 2)
  }

  // MARK: Cache key (EL-2.4)

  @Test func cacheKeyIsStableAndSensitive() async throws {
    let synth = try await makeSynth(http: RoutingHTTP(tts: okReply()))
    let base = try #require(synth.cacheKey(for: request()))
    #expect(synth.cacheKey(for: request()) == base)
    // Explicit defaults equal implicit defaults.
    #expect(synth.cacheKey(for: request(model: "eleven_v4", extra: ["stability": .double(0.5)])) == base)
    // Continuity text does not feed the key.
    #expect(synth.cacheKey(for: request(previous: "x", next: "y")) == base)

    #expect(synth.cacheKey(for: request("Hello there!")) != base)
    #expect(synth.cacheKey(for: request(model: "eleven_v3")) != base)
    #expect(synth.cacheKey(for: request(instruct: "(whispering)")) != base)
    #expect(synth.cacheKey(for: request(voice: .catalog(pluginId: "elevenlabs", voiceId: "other"))) != base)
    let changes: [String: SettingValue] = [
      "stability": .double(0.4), "similarity_boost": .double(0.7), "style": .double(0.1),
      "use_speaker_boost": .bool(false), "speed": .double(1.1), "seed": .int(3),
    ]
    for (k, v) in changes {
      #expect(synth.cacheKey(for: request(extra: [k: v])) != base, "\(k)")
    }
    // Instruct on a model that drops it does not change the audio, so not the key.
    let v2 = synth.cacheKey(for: request(model: "eleven_multilingual_v2"))
    #expect(synth.cacheKey(for: request(model: "eleven_multilingual_v2", instruct: "(sad)")) == v2)
    // Invalid requests have no key.
    #expect(synth.cacheKey(for: request(model: "nope")) == nil)
  }

  // MARK: Voices

  @Test func assetVoiceUsesTheVoxVoiceId() async throws {
    var asset = VoiceAsset(name: "Test", description: "A test voice for the synth.")
    try asset.setExtension(["voice_id": "voxVoice9", "model_id": "eleven_v4"], forEngine: "elevenlabs")
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("synth-test-\(UUID().uuidString).vox")
    try asset.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let http = RoutingHTTP(tts: okReply())
    let synth = try await makeSynth(http: http)
    let voice = VoiceReference.asset(url)
    guard case .ready(let source) = await synth.readiness(for: voice) else {
      Issue.record("not ready")
      return
    }
    #expect(source?.engine == "elevenlabs")
    let audio = try await synth.synthesize(request(voice: voice))
    #expect(http.ttsRequests.first?.url?.path == "/v1/text-to-speech/voxVoice9")
    #expect(audio.sourceUsed?.engine == "elevenlabs")
  }

  @Test func foreignAndMissingVoicesAreUnsupported() async throws {
    let synth = try await makeSynth(http: RoutingHTTP(tts: okReply()))
    for voice in [
      VoiceReference.catalog(pluginId: "apple", voiceId: "x"),
      .asset(URL(fileURLWithPath: "/nonexistent.vox")),
    ] {
      guard case .unsupported = await synth.readiness(for: voice) else {
        Issue.record("expected unsupported")
        continue
      }
      await #expect(throws: HablareError.self) { _ = try await synth.synthesize(request(voice: voice)) }
    }
  }

  @Test func missingKeyThrowsMissingCredential() async throws {
    let plugin = try await ElevenLabsPlugin(
      context: PluginContext(keys: InMemoryAPIKeyStore(), registry: PluginRegistry(plugins: [])),
      legacyKeychain: NoLegacy(), httpClient: RoutingHTTP(tts: okReply()))
    let synth = try #require(plugin.synthesizer)
    await #expect(throws: HablareError.self) { _ = try await synth.synthesize(request()) }
  }
}
