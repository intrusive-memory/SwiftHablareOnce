//
//  ElevenLabsModels.swift
//  SwiftHablareOnce
//
//  Model descriptors, per-model facts (SwiftOnce Docs/API-AUDIT.md, 2026-11-04) and the
//  settings schema (EL-1.3, EL-1.5).
//

import Foundation
import SwiftHablare

public enum ElevenLabsModels {
  /// Used wherever a project names no model (mission rule 5).
  public static let defaultModelId = "eleven_v4"

  /// Credit cost per character, from `model_rates.character_cost_multiplier`.
  public static func costFactor(forModel id: String) -> Double {
    switch id {
    case "eleven_v4_turbo", "eleven_v3_conversational", "eleven_flash_v2_5", "eleven_turbo_v2_5",
      "eleven_turbo_v2", "eleven_flash_v2":
      return 0.5
    default:
      return 1.0
    }
  }

  /// Per-request character limit for a known model; `nil` for an id this release does not know.
  public static func maxCharacters(forModel id: String) -> Int? {
    switch id {
    case "eleven_v4", "eleven_v4_turbo", "eleven_multilingual_v2": return 10_000
    case "eleven_v3", "eleven_v3_conversational": return 5_000
    case "eleven_flash_v2_5", "eleven_turbo_v2_5": return 40_000
    case "eleven_turbo_v2", "eleven_flash_v2": return 30_000
    default: return nil
    }
  }

  /// Limit used for a valid model id this release does not know.
  public static let conservativeMaxCharacters = 5_000

  /// The limit the synthesizer enforces: the audit value, else ``conservativeMaxCharacters``.
  public static func effectiveMaxCharacters(forModel id: String) -> Int {
    maxCharacters(forModel: id) ?? conservativeMaxCharacters
  }

  /// Models that take audio tags, so `.instruct` is meaningful (EL-1.6): `eleven_v3` and
  /// every `eleven_v4*`. An unknown id never qualifies unless it starts with `eleven_v4`.
  public static func supportsAudioTags(model id: String) -> Bool {
    id == "eleven_v3" || id.hasPrefix("eleven_v4")
  }

  /// A model id is accepted when it matches `^eleven_[a-z0-9_]+$` (EL-1.3), so a model
  /// ElevenLabs ships later works without a plugin release.
  public static func isValidModelId(_ id: String) -> Bool {
    let prefix = "eleven_"
    guard id.hasPrefix(prefix), id.utf8.count > prefix.utf8.count else { return false }
    return id.utf8.dropFirst(prefix.utf8.count).allSatisfy {
      ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x5F
    }
  }

  public static let descriptors: [ModelDescriptor] = [
    descriptor("eleven_v4", "Eleven v4"),
    descriptor("eleven_v4_turbo", "Eleven v4 Turbo"),
    descriptor("eleven_v3", "Eleven v3"),
    descriptor("eleven_multilingual_v2", "Multilingual v2"),
    descriptor("eleven_flash_v2_5", "Flash v2.5"),
  ]

  private static func descriptor(_ id: String, _ name: String) -> ModelDescriptor {
    ModelDescriptor(
      id: id, displayName: name, kind: .cloud,
      capabilities: supportsAudioTags(model: id) ? [.instruct] : [])
  }

  /// EL-1.5. Defaults are ElevenLabs' own; `seed` has none (unseeded by default).
  public static let settingsSchema = SettingsSchema([
    SettingDefinition(
      key: SettingKey.model, valueType: .string,
      defaultValue: .string(defaultModelId),
      label: "Model",
      help: "ElevenLabs model id matching ^eleven_[a-z0-9_]+$; any such id is passed through."),
    SettingDefinition(
      key: SettingKey.stability, valueType: .double, range: 0...1,
      defaultValue: .double(0.5), label: "Stability", step: 0.05),
    SettingDefinition(
      key: SettingKey.similarityBoost, valueType: .double, range: 0...1,
      defaultValue: .double(0.75), label: "Similarity boost", step: 0.05),
    SettingDefinition(
      key: SettingKey.style, valueType: .double, range: 0...1,
      defaultValue: .double(0), label: "Style", step: 0.05),
    SettingDefinition(
      key: SettingKey.useSpeakerBoost, valueType: .bool,
      defaultValue: .bool(true), label: "Speaker boost"),
    SettingDefinition(
      key: SettingKey.speed, valueType: .double, range: 0.7...1.2,
      defaultValue: .double(1.0), label: "Speed", step: 0.05),
    SettingDefinition(
      key: SettingKey.seed, valueType: .int, range: 0...Double(UInt32.max),
      label: "Seed", help: "Best-effort determinism (UInt32)."),
    SettingDefinition(
      key: SettingKey.maxConcurrentRequests, valueType: .int, range: 1...32,
      defaultValue: .int(defaultMaxConcurrentRequests), scope: .perPlugin,
      label: "Max concurrent requests",
      help: "Parallel ElevenLabs requests; keep at or below your plan's limit (EL-2.5)."),
  ])

  /// EL-2.5. Safe for every plan, including Free.
  public static let defaultMaxConcurrentRequests = 2

  /// Setting keys, as they appear in `SpeechRequest.settings`.
  public enum SettingKey {
    public static let model = "model"
    public static let stability = "stability"
    public static let similarityBoost = "similarity_boost"
    public static let style = "style"
    public static let useSpeakerBoost = "use_speaker_boost"
    public static let speed = "speed"
    public static let seed = "seed"
    /// Plugin-wide (`PluginConfiguration`), not per voice.
    public static let maxConcurrentRequests = "max_concurrent_requests"
  }
}
