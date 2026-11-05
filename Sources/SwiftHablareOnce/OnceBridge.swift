//
//  OnceBridge.swift
//  SwiftHablareOnce
//
//  Isolated from SwiftHablare so SwiftOnce's `VoiceSettings` is unambiguous (Hablare has its
//  own, and the `SwiftOnce` actor shadows the module name for qualification).
//

import Foundation
import SwiftOnce

func onceVoiceSettings(
  stability: Double, similarityBoost: Double, style: Double, speed: Double,
  useSpeakerBoost: Bool
) -> VoiceSettings {
  VoiceSettings(
    stability: stability, similarityBoost: similarityBoost, style: style, speed: speed,
    useSpeakerBoost: useSpeakerBoost)
}
