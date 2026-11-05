//
//  ElevenLabsSynthesizer.swift
//  SwiftHablareOnce
//
//  The `VoiceSynthesizer` role for ElevenLabs (EL-1.4, EL-1.6 to EL-1.9, EL-2.4, EL-2.5).
//

import CryptoKit
import Foundation
import SwiftHablare
import SwiftOnce

public struct ElevenLabsSynthesizer: VoiceSynthesizer {
  let plugin: ElevenLabsPlugin

  init(plugin: ElevenLabsPlugin) { self.plugin = plugin }

  // MARK: Static description

  /// Describes the default model; per-request values follow the request's `model` setting
  /// (see ``capabilities(forModel:)`` and ``limits(forModel:)``).
  public var capabilities: SynthesisCapabilities {
    capabilities(forModel: ElevenLabsModels.defaultModelId)
  }

  public var limits: SynthesisLimits { limits(forModel: ElevenLabsModels.defaultModelId) }

  public func capabilities(forModel model: String) -> SynthesisCapabilities {
    // `.seed`: ElevenLabs seeds are best-effort, but the cache key includes the seed.
    ElevenLabsModels.supportsAudioTags(model: model) ? [.instruct, .seed] : [.seed]
  }

  public func limits(forModel model: String) -> SynthesisLimits {
    SynthesisLimits(maxCharacters: ElevenLabsModels.effectiveMaxCharacters(forModel: model))
  }

  public var nativeFormats: [AudioFormat] { [.pcm24kMono16] }

  /// Default 2 (EL-2.5); set `max_concurrent_requests` in `PluginConfiguration`.
  public var maxConcurrentRequests: Int { plugin.maxConcurrentRequests }

  /// What a `pcm_24000` response is wrapped as.
  public static let returnedFormat = AudioFormat(
    container: .wav, sampleRate: 24_000, channels: 1, bitDepth: 16)

  // MARK: Readiness

  public func readiness(for voice: VoiceReference) async -> VoiceReadiness {
    do {
      let resolved = try Self.resolve(voice)
      return .ready(source: resolved.source)
    } catch {
      return .unsupported(reason: Self.reason(of: error))
    }
  }

  public func prepare(_ voice: VoiceReference) async throws { _ = try Self.resolve(voice) }

  public func release(_ voice: VoiceReference) async {}

  // MARK: Synthesis

  public func synthesize(_ request: SpeechRequest) async throws -> GeneratedAudio {
    if Task.isCancelled { throw HablareError.cancelled }
    let prepared = try Self.prepare(request)
    guard let apiKey = plugin.resolveAPIKey() else {
      throw HablareError.missingCredential(
        pluginId: ElevenLabsPlugin.id,
        environmentVariable: CredentialRequirement.elevenLabs.primaryEnvironmentVariable)
    }

    // Quota check before spending anything (EL-1.8).
    switch await plugin.status(
      estimatingCharacters: prepared.text.count, model: prepared.settings.model)
    {
    case .unavailable(let reason) where reason == "quota": throw HablareError.quotaExceeded
    case .needsCredential(let envVar):
      throw HablareError.missingCredential(
        pluginId: ElevenLabsPlugin.id, environmentVariable: envVar)
    default: break
    }

    let client = plugin.onceClient(apiKey: apiKey)
    let s = prepared.settings
    do {
      let result = try await client.speakResult(
        prepared.text, voice: prepared.voice.voiceId, model: Model(s.model),
        outputFormat: .pcm_24000, languageCode: request.languageCode,
        voiceSettings: onceVoiceSettings(
          stability: s.stability, similarityBoost: s.similarityBoost, style: s.style,
          speed: s.speed, useSpeakerBoost: s.useSpeakerBoost),
        seed: s.seed, previousText: request.previousText, nextText: request.nextText)
      return GeneratedAudio(
        data: Self.wavWrapping(pcm: result.audio),
        format: Self.returnedFormat,
        duration: Double(result.audio.count / 2) / 24_000,
        droppedInstruct: prepared.droppedInstruct,
        sourceUsed: prepared.voice.source)
    } catch {
      throw Self.mapped(error, apiKey: apiKey)
    }
  }

  // MARK: Cost and cache (EL-1.8, EL-2.4)

  public func estimateCost(_ request: SpeechRequest) -> CostEstimate? {
    guard let prepared = try? Self.prepare(request, requireVoice: false) else { return nil }
    return CostEstimate(
      quantity: Double(
        ElevenLabsPlugin.estimateCost(
          characters: prepared.text.count, model: prepared.settings.model)),
      unit: .credits)
  }

  /// SHA-256 over provider id, model, voice id, every (default-filled) setting, the effective
  /// seed, language, text and the mapped audio tag. `previousText` / `nextText` are excluded
  /// on purpose: they shape prosody at the seams, and one edited line must not invalidate its
  /// neighbours (EL-2.4). The tag is empty when the model drops `instruct`, since the audio
  /// is then identical. `nil` when the request would not validate.
  public func cacheKey(for request: SpeechRequest) -> String? {
    guard let prepared = try? Self.prepare(request) else { return nil }
    var hasher = SHA256()
    func field(_ label: String, _ value: String) {
      let bytes = Array(value.utf8)
      hasher.update(data: Data("\(label):\(bytes.count):".utf8))
      hasher.update(data: Data(bytes))
      hasher.update(data: Data("\n".utf8))
    }
    field("provider", ElevenLabsPlugin.id)
    field("model", prepared.settings.model)
    field("voice", prepared.voice.voiceId)
    for (key, value) in prepared.settings.all.sorted(by: { $0.key < $1.key }) {
      field("setting.\(key)", value)
    }
    field("seed", prepared.settings.seed.map(String.init) ?? "none")
    field("language", request.languageCode ?? "")
    field("text", request.text)
    field("instruct", prepared.tag ?? "")
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}

// MARK: - Request preparation

extension ElevenLabsSynthesizer {
  struct ResolvedVoice {
    var voiceId: String
    var source: VoiceSource?
  }

  struct ResolvedSettings {
    var model: String
    var stability: Double
    var similarityBoost: Double
    var style: Double
    var speed: Double
    var useSpeakerBoost: Bool
    var seed: Int?

    /// Every setting except `seed`, as stable strings for the cache key.
    var all: [String: String] {
      [
        "model": model, "stability": "\(stability)", "similarity_boost": "\(similarityBoost)",
        "style": "\(style)", "speed": "\(speed)", "use_speaker_boost": "\(useSpeakerBoost)",
      ]
    }
  }

  struct Prepared {
    var voice: ResolvedVoice
    var settings: ResolvedSettings
    /// Text as sent: the audio tag (if any) then the line.
    var text: String
    /// `[whispering]`, or `nil` when none was given or the model drops it.
    var tag: String?
    var droppedInstruct: Bool
  }

  static func prepare(_ request: SpeechRequest, requireVoice: Bool = true) throws -> Prepared {
    let settings = try resolveSettings(request)
    let voice =
      requireVoice
      ? try resolve(request.voice) : ((try? resolve(request.voice)) ?? ResolvedVoice(voiceId: ""))
    guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw HablareError.invalidRequest(detail: "text is empty")
    }

    var tag: String?
    var dropped = false
    if let instruct = request.instruct,
      let mapped = audioTag(from: instruct)
    {
      if ElevenLabsModels.supportsAudioTags(model: settings.model) {
        tag = mapped
      } else {
        dropped = true
      }
    }
    let text = tag.map { "\($0) \(request.text)" } ?? request.text

    let limit = ElevenLabsModels.effectiveMaxCharacters(forModel: settings.model)
    guard text.count <= limit else {
      throw HablareError.invalidRequest(
        detail: "text is \(text.count) characters; \(settings.model) allows \(limit)")
    }
    return Prepared(
      voice: voice, settings: settings, text: text, tag: tag, droppedInstruct: dropped)
  }

  /// `(whispering)` or `[whispering]` or `whispering` becomes `[whispering]` (EL-1.6).
  static func audioTag(from instruct: String) -> String? {
    var inner = instruct.trimmingCharacters(in: .whitespacesAndNewlines)
    if let first = inner.first, let last = inner.last, inner.count >= 2,
      (first == "(" && last == ")") || (first == "[" && last == "]")
    {
      inner = String(inner.dropFirst().dropLast())
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return inner.isEmpty ? nil : "[\(inner)]"
  }

  static func resolveSettings(_ request: SpeechRequest) throws -> ResolvedSettings {
    let v = try request.settings.validated(
      against: ElevenLabsPlugin.settingsSchema, scope: .perVoice)
    func double(_ key: String, _ fallback: Double) -> Double {
      if case .double(let d)? = v[key] { return d }
      return fallback
    }
    var model = ElevenLabsModels.defaultModelId
    switch v[ElevenLabsModels.SettingKey.model] {
    case .string(let id)?, .choice(let id)?: model = id
    default: break
    }
    guard ElevenLabsModels.isValidModelId(model) else {
      throw HablareError.invalidRequest(
        detail: "setting 'model' must match ^eleven_[a-z0-9_]+$, got '\(model)'")
    }
    var useBoost = true
    if case .bool(let b)? = v[ElevenLabsModels.SettingKey.useSpeakerBoost] { useBoost = b }

    var seed: Int?
    if let requestSeed = request.seed {
      guard requestSeed <= UInt64(UInt32.max) else {
        throw HablareError.invalidRequest(detail: "seed \(requestSeed) exceeds UInt32")
      }
      seed = Int(requestSeed)
    } else if case .int(let s)? = v[ElevenLabsModels.SettingKey.seed] {
      seed = s
    }
    return ResolvedSettings(
      model: model,
      stability: double(ElevenLabsModels.SettingKey.stability, 0.5),
      similarityBoost: double(ElevenLabsModels.SettingKey.similarityBoost, 0.75),
      style: double(ElevenLabsModels.SettingKey.style, 0),
      speed: double(ElevenLabsModels.SettingKey.speed, 1.0),
      useSpeakerBoost: useBoost, seed: seed)
  }

  /// `.catalog(pluginId: "elevenlabs", voiceId:)`, or `.asset(URL)` whose `.vox` has
  /// `manifest.extensions.elevenlabs.voice_id`.
  static func resolve(_ voice: VoiceReference) throws -> ResolvedVoice {
    switch voice {
    case .catalog(let pluginId, let voiceId):
      guard pluginId == ElevenLabsPlugin.id else {
        throw HablareError.unsupportedVoice(voice, reason: "not an elevenlabs catalog voice")
      }
      guard !voiceId.isEmpty else {
        throw HablareError.unsupportedVoice(voice, reason: "empty voice id")
      }
      return ResolvedVoice(voiceId: voiceId, source: nil)
    case .asset(let url):
      let asset: VoiceAsset
      do { asset = try VoiceAsset(contentsOf: url) } catch {
        throw HablareError.unsupportedVoice(voice, reason: "cannot read .vox file")
      }
      guard let fields = asset.extensionFields(forEngine: ElevenLabsPlugin.id),
        let voiceId = fields["voice_id"] as? String, !voiceId.isEmpty
      else {
        throw HablareError.unsupportedVoice(
          voice, reason: "no extensions.elevenlabs.voice_id in the .vox")
      }
      let source = asset.sources.first {
        $0.engine == ElevenLabsPlugin.id && $0.kind == .serverHandle
      }
      return ResolvedVoice(voiceId: voiceId, source: source)
    }
  }

  private static func reason(of error: Error) -> String {
    if case HablareError.unsupportedVoice(_, let reason) = error { return reason }
    return String(describing: error)
  }
}

// MARK: - WAV

extension ElevenLabsSynthesizer {
  /// Wraps little-endian 16-bit mono 24 kHz PCM in a 44-byte RIFF/WAVE header.
  static func wavWrapping(pcm: Data, sampleRate: Int = 24_000) -> Data {
    var header = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) } }
    header.append(contentsOf: Array("RIFF".utf8))
    u32(UInt32(36 + pcm.count))
    header.append(contentsOf: Array("WAVEfmt ".utf8))
    u32(16)
    u16(1)  // PCM
    u16(1)  // mono
    u32(UInt32(sampleRate))
    u32(UInt32(sampleRate * 2))  // byte rate
    u16(2)  // block align
    u16(16)  // bits per sample
    header.append(contentsOf: Array("data".utf8))
    u32(UInt32(pcm.count))
    return header + pcm
  }
}

// MARK: - Errors (EL-1.9)

extension ElevenLabsSynthesizer {
  /// Maps SwiftOnce errors to categorised `HablareError`s. Nothing here carries the key:
  /// response bodies are dropped for server errors and scrubbed elsewhere.
  static func mapped(_ error: Error, apiKey: String) -> Error {
    // A cancelled task surfaces from URLSession as URLError.cancelled, which SwiftOnce wraps.
    if error is CancellationError || Task.isCancelled { return HablareError.cancelled }
    if let hablare = error as? HablareError { return hablare }
    guard let once = error as? ElevenLabsError else {
      return HablareError.transient(underlying: Sanitized(scrub(String(describing: error), apiKey)))
    }
    switch once {
    case .invalidAPIKey:
      return HablareError.invalidRequest(detail: "ElevenLabs API key rejected (HTTP 401)")
    case .quotaExceeded:
      return HablareError.quotaExceeded
    case .rateLimited(let seconds):
      return HablareError.rateLimited(retryAfter: seconds.map(TimeInterval.init))
    case .httpError(let status, _):
      if (500...599).contains(status) || status == 408 {
        return HablareError.transient(underlying: Sanitized("ElevenLabs HTTP \(status)"))
      }
      return HablareError.invalidRequest(detail: "ElevenLabs HTTP \(status)")
    case .voiceNotFound:
      return HablareError.invalidRequest(detail: "ElevenLabs voice not found")
    case .invalidRequest(let body):
      return HablareError.invalidRequest(detail: scrub("ElevenLabs rejected the request: \(body)", apiKey))
    case .textTooLong(let model, let limit, let count):
      return HablareError.invalidRequest(
        detail: "text is \(count) characters; \(model) allows \(limit)")
    case .networkError(let underlying):
      return HablareError.transient(underlying: Sanitized(scrub(String(describing: underlying), apiKey)))
    default:
      return HablareError.transient(underlying: Sanitized(scrub(String(describing: once), apiKey)))
    }
  }

  static func scrub(_ text: String, _ apiKey: String) -> String {
    apiKey.isEmpty ? text : text.replacingOccurrences(of: apiKey, with: "***")
  }

  struct Sanitized: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
  }
}
