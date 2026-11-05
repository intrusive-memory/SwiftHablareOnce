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

  /// Per-request character limit.
  public static func maxCharacters(forModel id: String) -> Int? {
    switch id {
    case "eleven_v4", "eleven_v4_turbo", "eleven_multilingual_v2": return 10_000
    case "eleven_v3": return 5_000
    case "eleven_flash_v2_5": return 40_000
    default: return nil
    }
  }

  /// Models that take audio tags, so `.instruct` is meaningful (EL-1.6).
  static let instructModels: Set<String> = ["eleven_v3", "eleven_v4", "eleven_v4_turbo"]

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
      capabilities: instructModels.contains(id) ? [.instruct] : [])
  }

  /// EL-1.5. Defaults are ElevenLabs' own; `seed` has none (unseeded by default).
  public static let settingsSchema = SettingsSchema([
    SettingDefinition(
      key: SettingKey.model, valueType: .choice,
      choices: descriptors.map(\.id), defaultValue: .choice(defaultModelId),
      label: "Model", help: "ElevenLabs text-to-speech model."),
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
  ])

  /// Setting keys, as they appear in `SpeechRequest.settings`.
  public enum SettingKey {
    public static let model = "model"
    public static let stability = "stability"
    public static let similarityBoost = "similarity_boost"
    public static let style = "style"
    public static let useSpeakerBoost = "use_speaker_boost"
    public static let speed = "speed"
    public static let seed = "seed"
  }
}
