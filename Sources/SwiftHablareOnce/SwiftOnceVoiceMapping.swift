//
//  SwiftOnceVoiceMapping.swift
//  SwiftHablareOnce
//
//  Voice model mapping between SwiftOnce and SwiftHablare
//

import Foundation
import SwiftHablare
import SwiftOnce

// MARK: - Voice Conversion

/// Convert SwiftOnce Voice to SwiftHablare Voice
///
/// Uses runtime casting to work around module/type name collision
internal func convertToHablareVoice(_ voiceAny: Any) -> HablareVoice {
  // Use Mirror to access properties dynamically
  let mirror = Mirror(reflecting: voiceAny)

  var voiceId: String = ""
  var name: String = ""
  var description: String?
  var verifiedLanguages: [Any]?
  var labels: [String: String] = [:]
  var category: Any?

  for child in mirror.children {
    switch child.label {
    case "voiceId":
      voiceId = child.value as? String ?? ""
    case "name":
      name = child.value as? String ?? ""
    case "description":
      description = child.value as? String
    case "verifiedLanguages":
      verifiedLanguages = child.value as? [Any]
    case "labels":
      labels = child.value as? [String: String] ?? [:]
    case "category":
      category = child.value
    default:
      break
    }
  }

  // Extract primary language from verifiedLanguages
  let primaryLanguage: String? = {
    guard let langs = verifiedLanguages, let firstLang = langs.first else {
      return nil
    }
    let langMirror = Mirror(reflecting: firstLang)
    for child in langMirror.children {
      if child.label == "locale", let locale = child.value as? String {
        return locale
      }
      if child.label == "language", let language = child.value as? String {
        return language
      }
    }
    return nil
  }()

  // Extract locality from primary language (e.g., "en-US" → "US")
  let locality: String? = {
    if let lang = primaryLanguage, lang.contains("-") {
      return String(lang.split(separator: "-").last ?? "")
    }
    return nil
  }()

  // Determine gender from labels if available
  let gender: String? = labels["gender"] ?? labels["accent"]

  // Map category to quality
  let quality: String? = {
    guard let cat = category else {
      return nil
    }
    let catString = String(describing: cat)
    if catString.contains("professional") || catString.contains("highQuality") {
      return "premium"
    } else if catString.contains("premade") {
      return "enhanced"
    } else if catString.contains("cloned") || catString.contains("generated") {
      return "default"
    }
    return nil
  }()

  return HablareVoice(
    id: voiceId,
    name: name,
    description: description,
    providerId: "elevenlabs",
    language: primaryLanguage,
    locality: locality,
    gender: gender,
    quality: quality
  )
}

// MARK: - Model Mapping

extension ElevenLabsModel {
  /// Convert SwiftHablare ElevenLabsModel to SwiftOnce Model
  internal func toSwiftOnceModel() -> Model {
    switch self {
    case .multilingualV2:
      return .multilingualV2
    case .turboV2_5:
      return .turboV2_5
    case .turboV2:
      return .turboV2
    case .multilingualV1:
      return .multilingualV1
    case .monolingualV1:
      return .monolingualV1
    }
  }
}
