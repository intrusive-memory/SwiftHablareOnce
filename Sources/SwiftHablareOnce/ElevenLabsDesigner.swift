//
//  ElevenLabsDesigner.swift
//  SwiftHablareOnce
//
//  The `VoiceDesigner` role for ElevenLabs (EL-1.10, EL-3.2): design previews, create the
//  permanent voice, write the `.vox` extension and sample, delete.
//

import AVFoundation
import Foundation
import SwiftHablare
import SwiftOnce

public struct ElevenLabsDesigner: VoiceDesigner {
  /// The default design model (SwiftOnce Docs/API-AUDIT.md section 3).
  public static let defaultDesignModel = "eleven_multilingual_ttv_v2"
  /// The design models the API accepts.
  public static let designModels = ["eleven_multilingual_ttv_v2", "eleven_ttv_v3"]
  /// ElevenLabs requires the sample line to be 100...1000 characters.
  public static let sampleTextLengthRange = 100...1000

  let plugin: ElevenLabsPlugin
  /// Name of the permanent voice created by ``save(_:into:)``; Echada passes
  /// `<project> — <CHARACTER>`. When `nil`, the `.vox` asset's own name is used.
  public let voiceName: String?
  /// `eleven_multilingual_ttv_v2` (default) or `eleven_ttv_v3`.
  public let designModel: String

  init(
    plugin: ElevenLabsPlugin, voiceName: String? = nil,
    designModel: String = ElevenLabsDesigner.defaultDesignModel
  ) {
    self.plugin = plugin
    self.voiceName = voiceName
    self.designModel = designModel
  }

  public var producedSources: [VoiceSourcePattern] {
    [
      VoiceSourcePattern(engine: ElevenLabsPlugin.id, kind: .referenceAudio),
      VoiceSourcePattern(engine: ElevenLabsPlugin.id, kind: .serverHandle),
    ]
  }

  // MARK: Design

  /// One `POST /v1/text-to-voice/design`. ElevenLabs decides how many previews come back
  /// (currently three); each becomes a candidate. The preview is a 16-bit PCM WAV.
  public func design(_ request: VoiceDesignRequest) async throws -> [VoiceCandidate] {
    let count = request.sampleText.count
    guard Self.sampleTextLengthRange.contains(count) else {
      throw HablareError.invalidRequest(
        detail:
          "voice design sample text must be 100 to 1000 characters; got \(count)")
    }
    guard
      let model = VoiceDesignModel(rawValue: designModel)
    else {
      throw HablareError.invalidRequest(
        detail:
          "unknown design model '\(designModel)'; use \(Self.designModels.joined(separator: " or "))"
      )
    }
    let apiKey = try requireKey()
    let client = plugin.onceClient(apiKey: apiKey)
    let response: VoiceDesignResponse
    do {
      response = try await client.designVoice(
        description: request.description, previewText: request.sampleText, model: model,
        loudness: nil, guidanceScale: nil, seed: nil, autoGenerateText: nil,
        outputFormat: .pcm_24000)
    } catch {
      throw await mapped(error, apiKey: apiKey, client: client)
    }

    let context = CandidateContext(designModel: designModel, sampleText: request.sampleText)
    let payload = try JSONEncoder().encode(context)
    var candidates: [VoiceCandidate] = []
    for preview in response.previews {
      let wav: DecodedWAV
      do { wav = try Self.previewWAV(from: preview) } catch {
        throw HablareError.invalidRequest(
          detail: "cannot decode voice preview audio (\(preview.mediaType))")
      }
      await plugin.previewCache.store(preview)
      candidates.append(
        VoiceCandidate(
          preview: GeneratedAudio(
            data: wav.data,
            format: AudioFormat(
              container: .wav, sampleRate: wav.sampleRate, channels: wav.channels, bitDepth: 16),
            duration: wav.duration),
          handle: VoiceCandidate.Handle(identifier: preview.id, payload: payload),
          promptSent: request.description))
    }
    return candidates
  }

  // MARK: Save

  /// `POST /v1/text-to-voice` (permanent voice), then EL-3.2 into `asset`. Other engines'
  /// embeddings and extensions are left alone.
  ///
  /// Works across processes. The voice is created from `candidate.handle.identifier` (the
  /// `generated_voice_id`), the design model and sample text come from `handle.payload`, and the
  /// sample-audio entry is `candidate.preview`. A candidate returned by `design` carries all of
  /// that; a later process rebuilds one with ``candidate(generatedVoiceId:previewWAV:designModel:sampleText:description:)``.
  public func save(_ candidate: VoiceCandidate, into asset: inout VoiceAsset) async throws {
    let context =
      try candidate.handle.payload.flatMap {
        try? JSONDecoder().decode(CandidateContext.self, from: $0)
      }
      ?? CandidateContext(designModel: designModel, sampleText: "")
    let name = voiceName ?? asset.name
    let apiKey = try requireKey()
    let client = plugin.onceClient(apiKey: apiKey)
    let createdVoiceId: String
    do {
      createdVoiceId = try await client.createVoice(
        generatedVoiceId: candidate.handle.identifier, name: name,
        description: candidate.promptSent, labels: nil
      ).voiceId
    } catch {
      throw await mapped(error, apiKey: apiKey, client: client)
    }
    await plugin.previewCache.remove(id: candidate.handle.identifier)

    let stamp = ISO8601DateFormatter()
    stamp.formatOptions = [.withInternetDateTime]
    try asset.setExtension(
      [
        "voice_id": createdVoiceId,
        "generated_voice_id": candidate.handle.identifier,
        "design_model": context.designModel,
        "description_sent": candidate.promptSent,
        "sample_text": context.sampleText,
        "created_at": stamp.string(from: Date()),
      ], forEngine: ElevenLabsPlugin.id)
    try asset.addSampleAudio(
      candidate.preview.data, engine: ElevenLabsPlugin.id, model: context.designModel)
  }

  // MARK: Reconstructing a candidate

  /// Rebuilds a ``VoiceCandidate`` from persisted data so ``save(_:into:)`` can run in a later
  /// process than ``design(_:)``. Persist, per candidate: `candidate.handle.identifier`
  /// (`generatedVoiceId`), the preview WAV (`candidate.preview.data`), and the design inputs
  /// (the design model, the sample text, and `candidate.promptSent` as `description`).
  public static func candidate(
    generatedVoiceId: String, previewWAV: Data, designModel: String = defaultDesignModel,
    sampleText: String, description: String
  ) throws -> VoiceCandidate {
    let info = try wavInfo(previewWAV)
    let payload = try JSONEncoder().encode(
      CandidateContext(designModel: designModel, sampleText: sampleText))
    return VoiceCandidate(
      preview: GeneratedAudio(
        data: previewWAV,
        format: AudioFormat(
          container: .wav, sampleRate: info.sampleRate, channels: info.channels, bitDepth: 16),
        duration: info.duration),
      handle: VoiceCandidate.Handle(identifier: generatedVoiceId, payload: payload),
      promptSent: description)
  }

  // MARK: Delete

  /// `DELETE /v1/voices/{id}`, freeing the slot. Accepts `.catalog(pluginId: "elevenlabs", …)`
  /// and an `.asset` whose `.vox` has `extensions.elevenlabs.voice_id`.
  public func delete(_ voice: VoiceReference) async throws {
    let resolved = try ElevenLabsSynthesizer.resolve(voice)
    let apiKey = try requireKey()
    let client = plugin.onceClient(apiKey: apiKey)
    do { try await client.deleteVoice(resolved.voiceId) } catch {
      throw await mapped(error, apiKey: apiKey, client: client)
    }
  }

  // MARK: Helpers

  struct CandidateContext: Codable {
    var designModel: String
    var sampleText: String
    enum CodingKeys: String, CodingKey {
      case designModel = "design_model"
      case sampleText = "sample_text"
    }
  }

  private func requireKey() throws -> String {
    guard let key = plugin.resolveAPIKey() else {
      throw HablareError.missingCredential(
        pluginId: ElevenLabsPlugin.id,
        environmentVariable: CredentialRequirement.elevenLabs.primaryEnvironmentVariable)
    }
    return key
  }

  /// Like the synthesizer mapping, plus the voice-slot limit and the design-text rule.
  private func mapped(_ error: Error, apiKey: String, client: SwiftOnce) async -> Error {
    guard let once = error as? ElevenLabsError else {
      return ElevenLabsSynthesizer.mapped(error, apiKey: apiKey)
    }
    switch once {
    case .voiceLimitReached(let message):
      let limit = (try? await client.subscription())?.voiceLimit
      var detail =
        limit.map { "ElevenLabs voice limit reached (\($0) voice slots on this plan)" }
        ?? "ElevenLabs voice limit reached"
      detail += "; delete an unused voice or upgrade the plan"
      if let message, !message.isEmpty {
        detail += " (\(ElevenLabsSynthesizer.scrub(message, apiKey)))"
      }
      return HablareError.invalidRequest(detail: detail)
    case .invalidDesignText(let count):
      return HablareError.invalidRequest(
        detail: "voice design sample text must be 100 to 1000 characters; got \(count)")
    default:
      return ElevenLabsSynthesizer.mapped(error, apiKey: apiKey)
    }
  }

  // MARK: Audio

  struct DecodedWAV {
    var data: Data
    var sampleRate: Int
    var channels: Int
    var duration: TimeInterval
  }

  /// The preview as a WAV: raw PCM (requested as `pcm_24000`) gets a 44-byte header; anything
  /// else goes through the AVFoundation decode.
  static func previewWAV(from preview: VoicePreview) throws -> DecodedWAV {
    let data = preview.audioData
    let media = preview.mediaType.lowercased()
    let looksEncoded =
      data.starts(with: Array("RIFF".utf8)) || data.starts(with: Array("ID3".utf8))
      || (data.count > 1 && data[data.startIndex] == 0xFF
        && data[data.startIndex + 1] & 0xE0 == 0xE0)
      || media.contains("mpeg") || media.contains("mp3")
    if !looksEncoded || media.contains("pcm") || media.contains("l16") {
      guard data.count % 2 == 0 else { return try wav(from: data) }
      let rate = 24_000
      return DecodedWAV(
        data: ElevenLabsSynthesizer.wavWrapping(pcm: data, sampleRate: rate), sampleRate: rate,
        channels: 1, duration: Double(data.count / 2) / Double(rate))
    }
    return try wav(from: data)
  }

  /// Sample rate, channels and duration from a 16-bit PCM WAV header.
  static func wavInfo(_ wav: Data) throws -> (
    sampleRate: Int, channels: Int, duration: TimeInterval
  ) {
    let bytes = [UInt8](wav)
    guard bytes.count >= 44, wav.starts(with: Array("RIFF".utf8)) else {
      throw HablareError.invalidRequest(detail: "preview is not a WAV file")
    }
    func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
    func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
    let channels = u16(22)
    let rate = u32(24)
    let bits = u16(34)
    guard channels > 0, rate > 0, bits > 0 else {
      throw HablareError.invalidRequest(detail: "preview WAV header is invalid")
    }
    let frames = (bytes.count - 44) / (channels * bits / 8)
    return (rate, channels, Double(frames) / Double(rate))
  }

  /// A 16-bit PCM WAV for `audio`, which is already WAV or any format AVFoundation reads
  /// (ElevenLabs designs return MP3 by default).
  static func wav(from audio: Data) throws -> DecodedWAV {
    let temp = FileManager.default.temporaryDirectory
      .appendingPathComponent("SwiftHablareOnce-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let input = temp.appendingPathComponent("in.\(Self.fileExtension(of: audio))")
    try audio.write(to: input)
    let reader = try AVAudioFile(forReading: input)
    let format = reader.processingFormat
    let output = temp.appendingPathComponent("out.wav")
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: format.sampleRate,
      AVNumberOfChannelsKey: format.channelCount,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
    ]
    do {
      let writer = try AVAudioFile(forWriting: output, settings: settings)
      let capacity: AVAudioFrameCount = 16_384
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
        throw HablareError.invalidRequest(detail: "cannot allocate audio buffer")
      }
      while reader.framePosition < reader.length {
        try reader.read(into: buffer, frameCount: capacity)
        if buffer.frameLength == 0 { break }
        try writer.write(from: buffer)
      }
    }
    return DecodedWAV(
      data: try Data(contentsOf: output), sampleRate: Int(format.sampleRate),
      channels: Int(format.channelCount),
      duration: Double(reader.length) / format.sampleRate)
  }

  private static func fileExtension(of data: Data) -> String {
    if data.starts(with: Array("RIFF".utf8)) { return "wav" }
    if data.starts(with: Array("FORM".utf8)) { return "aiff" }
    if data.starts(with: Array("caff".utf8)) { return "caf" }
    return "mp3"
  }
}

/// Previews from `design`, kept so `save` can hand SwiftOnce the preview it asks for.
actor PreviewCache {
  private var previews: [String: VoicePreview] = [:]
  private var order: [String] = []
  private let capacity = 64

  func store(_ preview: VoicePreview) {
    if previews[preview.id] == nil { order.append(preview.id) }
    previews[preview.id] = preview
    while order.count > capacity { previews[order.removeFirst()] = nil }
  }

  func preview(id: String) -> VoicePreview? { previews[id] }

  func remove(id: String) {
    previews[id] = nil
    order.removeAll { $0 == id }
  }
}
