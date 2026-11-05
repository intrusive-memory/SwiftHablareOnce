//
//  ElevenLabsDesignerTests.swift
//  SwiftHablareOnceTests
//
//  Sortie 11. No network: SwiftOnce runs against a path-routing mock `HTTPClient`.
//

import AVFoundation
import Foundation
import SwiftHablare
import SwiftHablareTesting
import SwiftOnce
import Testing

@testable import SwiftHablareOnce

private let key = "sk_test_key_not_real_456"
private let sample = String(repeating: "The rain kept falling on the old harbour. ", count: 4)  // 168 chars

private struct NoLegacy: LegacyKeychainReading {
  func legacyAPIKey() -> String? { nil }
}

private final class DesignHTTP: HTTPClient, @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [URLRequest] = []
  var createStatus = 200
  var createBody = Data(#"{"voice_id":"perm_voice_1","name":"x","category":"generated"}"#.utf8)
  var voiceLimit = 30

  var requests: [URLRequest] { lock.withLock { recorded } }
  func requests(path: String) -> [URLRequest] { requests.filter { $0.url?.path == path } }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    lock.withLock { recorded.append(request) }
    var status = 200
    var body = Data()
    switch (request.httpMethod ?? "GET", request.url?.path ?? "") {
    case ("POST", "/v1/text-to-voice/design"):
      let wav = ElevenLabsSynthesizer.wavWrapping(pcm: Data(repeating: 1, count: 4_800))
      let previews = (1...3).map { i in
        """
        {"audio_base_64":"\(wav.base64EncodedString())","generated_voice_id":"gen_\(i)",\
        "media_type":"audio/wav","duration_secs":0.1,"language":"en"}
        """
      }
      body = Data(#"{"previews":[\#(previews.joined(separator: ","))],"text":"t"}"#.utf8)
    case ("POST", "/v1/text-to-voice"):
      status = createStatus
      body = createBody
    case ("DELETE", _):
      body = Data(#"{"status":"ok"}"#.utf8)
    case ("GET", "/v1/user/subscription"):
      body = Data(
        #"{"tier":"creator","status":"active","character_count":0,"character_limit":100000,"voice_limit":\#(voiceLimit),"voice_slots_used":\#(voiceLimit)}"#
          .utf8)
    default:
      status = 404
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    return (body, response)
  }
  func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
    throw URLError(.unsupportedURL)
  }
}

private func makePlugin(_ http: DesignHTTP) async throws -> ElevenLabsPlugin {
  let context = PluginContext(
    keys: InMemoryAPIKeyStore(keys: ["elevenlabs": key]), configuration: .empty,
    registry: PluginRegistry(plugins: []))
  return try await ElevenLabsPlugin(
    context: context, legacyKeychain: NoLegacy(), httpClient: http,
    onceConfiguration: SwiftOnceConfiguration(
      defaultModel: Model("eleven_v4"), maxRetries: 0))
}

private func json(_ req: URLRequest) throws -> [String: Any] {
  let data = try #require(req.httpBody)
  let object = try JSONSerialization.jsonObject(with: data)
  return try #require(object as? [String: Any])
}

@Suite struct ElevenLabsDesignerTests {

  @Test func pluginExposesDesigner() async throws {
    let plugin = try await makePlugin(DesignHTTP())
    #expect(plugin.designer is ElevenLabsDesigner)
    let designer = try #require(plugin.designer)
    #expect(designer.producedSources.contains(VoiceSourcePattern(engine: "elevenlabs", kind: .serverHandle)))
  }

  @Test func designReturnsCandidatesWithIdsAndWavPreviews() async throws {
    let http = DesignHTTP()
    let designer = try #require(try await makePlugin(http).designer)
    let candidates = try await designer.design(
      VoiceDesignRequest(description: "A gravelly old sailor", sampleText: sample))

    #expect(candidates.map(\.handle.identifier) == ["gen_1", "gen_2", "gen_3"])
    #expect(candidates.allSatisfy { $0.promptSent == "A gravelly old sailor" })
    let first = try #require(candidates.first)
    #expect(first.preview.format.container == .wav)
    #expect(first.preview.format.bitDepth == 16)
    #expect(String(decoding: first.preview.data.prefix(4), as: UTF8.self) == "RIFF")
    #expect(first.preview.duration > 0)

    let sent = try json(try #require(http.requests(path: "/v1/text-to-voice/design").first))
    #expect(sent["voice_description"] as? String == "A gravelly old sailor")
    #expect(sent["text"] as? String == sample)
    #expect(sent["model_id"] as? String == "eleven_multilingual_ttv_v2")
  }

  @Test func sampleTextOutsideRangeIsTypedErrorAndNothingIsSent() async throws {
    let http = DesignHTTP()
    let designer = try #require(try await makePlugin(http).designer)
    for text in ["too short", String(repeating: "x", count: 1001)] {
      do {
        _ = try await designer.design(VoiceDesignRequest(description: "d", sampleText: text))
        Issue.record("expected an error")
      } catch let error as HablareError {
        guard case .invalidRequest(let detail) = error else { Issue.record("\(error)"); return }
        #expect(detail.contains("100 to 1000"))
        #expect(error.category == .permanent)
      }
    }
    #expect(http.requests.isEmpty)
  }

  @Test func saveCreatesVoiceWritesExtensionAndSampleAndKeepsQwen() async throws {
    let http = DesignHTTP()
    let plugin = try await makePlugin(http)
    let designer = plugin.designer(voiceName: "Harbour — SAILOR")
    let candidates = try await designer.design(
      VoiceDesignRequest(description: "A gravelly old sailor", sampleText: sample))
    let chosen = candidates[1]

    var asset = VoiceAsset(name: "SAILOR", description: "old sailor")
    let qwenData = Data("clone-prompt".utf8)
    try asset.addEmbedding(qwenData, engine: "qwen3-tts", model: "Qwen/Qwen3-TTS-12Hz-0.6B")
    let qwenFields: [String: Any] = ["voice_id": "keep"]
    try asset.setExtension(qwenFields, forEngine: "qwen3-tts")
    let qwenPaths = asset.entryPaths.filter { $0.contains("qwen3-tts") }
    #expect(!qwenPaths.isEmpty)

    try await designer.save(chosen, into: &asset)

    let create = try json(try #require(http.requests(path: "/v1/text-to-voice").first))
    #expect(create["generated_voice_id"] as? String == "gen_2")
    #expect(create["voice_name"] as? String == "Harbour — SAILOR")
    #expect(create["voice_description"] as? String == "A gravelly old sailor")

    let fields = try #require(asset.extensionFields(forEngine: "elevenlabs"))
    #expect(Set(fields.keys) == [
      "voice_id", "generated_voice_id", "design_model", "description_sent", "sample_text",
      "created_at",
    ])
    #expect(fields["voice_id"] as? String == "perm_voice_1")
    #expect(fields["generated_voice_id"] as? String == "gen_2")
    #expect(fields["design_model"] as? String == "eleven_multilingual_ttv_v2")
    #expect(fields["description_sent"] as? String == "A gravelly old sailor")
    #expect(fields["sample_text"] as? String == sample)
    let created = try #require(fields["created_at"] as? String)
    #expect(ISO8601DateFormatter().date(from: created) != nil)

    let samplePath = "embeddings/elevenlabs/eleven_multilingual_ttv_v2/sample-audio.wav"
    #expect(asset.entryData(at: samplePath) == chosen.preview.data)

    // Existing qwen3-tts content is untouched.
    #expect(asset.entryPaths.filter { $0.contains("qwen3-tts") } == qwenPaths)
    for path in qwenPaths { #expect(asset.entryData(at: path) == qwenData) }
    #expect(asset.extensionFields(forEngine: "qwen3-tts")?["voice_id"] as? String == "keep")
    #expect(asset.sources.contains { $0.engine == "elevenlabs" && $0.kind == .serverHandle })
  }

  @Test func saveFallsBackToAssetNameWhenNoVoiceNameGiven() async throws {
    let http = DesignHTTP()
    let designer = try #require(try await makePlugin(http).designer)
    let candidates = try await designer.design(
      VoiceDesignRequest(description: "d", sampleText: sample))
    var asset = VoiceAsset(name: "Asset Name", description: "x")
    try await designer.save(candidates[0], into: &asset)
    let create = try json(try #require(http.requests(path: "/v1/text-to-voice").first))
    #expect(create["voice_name"] as? String == "Asset Name")
  }

  @Test func deleteIssuesDeleteForCatalogAndAssetReferences() async throws {
    let http = DesignHTTP()
    let designer = try #require(try await makePlugin(http).designer)
    try await designer.delete(.catalog(pluginId: "elevenlabs", voiceId: "abc123"))

    var asset = VoiceAsset(name: "N", description: "d")
    try asset.setExtension(["voice_id": "def456"], forEngine: "elevenlabs")
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).vox")
    defer { try? FileManager.default.removeItem(at: url) }
    try asset.write(to: url)
    try await designer.delete(.asset(url))

    let deletes = http.requests.filter { $0.httpMethod == "DELETE" }
    #expect(deletes.compactMap { $0.url?.path } == ["/v1/voices/abc123", "/v1/voices/def456"])

    await #expect(throws: HablareError.self) {
      try await designer.delete(.catalog(pluginId: "other", voiceId: "x"))
    }
  }

  @Test func voiceLimitIsTypedPermanentErrorNamingTheLimit() async throws {
    let http = DesignHTTP()
    http.createStatus = 400
    http.createBody = Data(
      #"{"detail":{"status":"voice_limit_reached","message":"Slots full"}}"#.utf8)
    let designer = try #require(try await makePlugin(http).designer)
    let candidates = try await designer.design(
      VoiceDesignRequest(description: "d", sampleText: sample))
    var asset = VoiceAsset(name: "N", description: "d")
    do {
      try await designer.save(candidates[0], into: &asset)
      Issue.record("expected an error")
    } catch let error as HablareError {
      guard case .invalidRequest(let detail) = error else { Issue.record("\(error)"); return }
      #expect(error.category == .permanent)
      #expect(detail.contains("voice limit reached"))
      #expect(detail.contains("30 voice slots"))
      #expect(!detail.contains(key))
    }
    #expect(asset.extensionFields(forEngine: "elevenlabs") == nil)
  }

  @Test func saveRejectsACandidateFromAnotherPluginInstance() async throws {
    let designerA = try #require(try await makePlugin(DesignHTTP()).designer)
    let candidates = try await designerA.design(
      VoiceDesignRequest(description: "d", sampleText: sample))
    let designerB = try #require(try await makePlugin(DesignHTTP()).designer)
    var asset = VoiceAsset(name: "N", description: "d")
    await #expect(throws: HablareError.self) {
      try await designerB.save(candidates[0], into: &asset)
    }
  }

  @Test func nonWavPreviewIsConvertedToWav() throws {
    // CAF stands in for MP3: AVFoundation reads both, and MP3 cannot be written here.
    let dir = FileManager.default.temporaryDirectory
    let url = dir.appendingPathComponent("\(UUID().uuidString).caf")
    defer { try? FileManager.default.removeItem(at: url) }
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410)!
    buffer.frameLength = 4_410
    do {
      let file = try AVAudioFile(forWriting: url, settings: format.settings)
      try file.write(from: buffer)
    }
    let decoded = try ElevenLabsDesigner.wav(from: try Data(contentsOf: url))
    #expect(String(decoding: decoded.data.prefix(4), as: UTF8.self) == "RIFF")
    #expect(decoded.sampleRate == 44_100)
    #expect(decoded.channels == 1)
    #expect(abs(decoded.duration - 0.1) < 0.001)
  }
}
