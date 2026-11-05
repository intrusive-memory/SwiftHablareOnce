//
//  ElevenLabsLiveTests.swift
//  SwiftHablareOnceLiveTests
//
//  Sortie 12. Real ElevenLabs calls, kept out of `make test` (a separate target that
//  `make test` skips) and gated twice: they run only when `ELEVENLABS_API_KEY` is set and
//  `GITHUB_ACTIONS` is not "true". Run them with `make test-live`.
//
//  Spend budget: one short line (under 60 characters, plus an audio tag), one design call
//  (three previews). The designed voice is deleted before the test returns, pass or fail.
//  The key is read from the environment only and never printed.
//

import Foundation
import SwiftHablare
import SwiftHablareTesting
import SwiftOnce
import Testing

@testable import SwiftHablareOnce

private let environment = ProcessInfo.processInfo.environment
private let liveKey = environment["ELEVENLABS_API_KEY"] ?? ""
private let liveEnabled = !liveKey.isEmpty && environment["GITHUB_ACTIONS"] != "true"
private let skipReason: Comment =
  "Live ElevenLabs tests need ELEVENLABS_API_KEY and run only outside GitHub Actions (make test-live)"

private func makePlugin() async throws -> ElevenLabsPlugin {
  let keys = InMemoryAPIKeyStore(keys: [ElevenLabsPlugin.keyAccount: liveKey])
  return try await ElevenLabsPlugin(
    context: PluginContext(keys: keys, registry: PluginRegistry(plugins: [])))
}

private func log(_ line: String) { print("[live] \(line)") }

private func wavHeader(_ data: Data) -> (sampleRate: Int, channels: Int, bits: Int)? {
  let b = [UInt8](data)
  guard b.count >= 44, data.prefix(4) == Data("RIFF".utf8),
    data.subdata(in: 8..<12) == Data("WAVE".utf8)
  else { return nil }
  func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
  func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
  return (u32(24), u16(22), u16(34))
}

@Suite(.serialized) struct ElevenLabsLiveTests {

  @Test(.enabled(if: liveEnabled, skipReason))
  func synthesizesOneLineOnV4AndAcceptsAnAudioTag() async throws {
    let plugin = try await makePlugin()
    let client = plugin.onceClient(apiKey: liveKey)

    // Free read-only call: a premade voice id.
    let list = try await client.voices(category: .premade, pageSize: 5)
    let premade = try #require(list.voices.first, "no premade voice returned by GET /v2/voices")
    log("premade voice chosen: \(premade.name)")

    let line = "The harbor lights are coming on."  // 32 characters
    #expect(line.count <= 60)
    let synth = try #require(plugin.synthesizer)
    let request = SpeechRequest(
      text: line, voice: .catalog(pluginId: "elevenlabs", voiceId: premade.voiceId),
      instruct: "whispering",
      settings: VoiceSettings(["model": .string("eleven_v4")]))

    let audio = try await synth.synthesize(request)
    log(
      "eleven_v4 accepted '[whispering] <line>' (HTTP 200); droppedInstruct=\(String(describing: audio.droppedInstruct))"
    )
    log("duration \(audio.duration) s for \(line.count) characters plus tag")
    let header = try #require(wavHeader(audio.data), "response is not a RIFF/WAVE file")
    #expect(header.sampleRate == 24_000)
    #expect(header.channels == 1)
    #expect(header.bits == 16)
    #expect(audio.duration > 0.5, "duration \(audio.duration) s is trivially short")
    #expect(audio.droppedInstruct == false, "eleven_v4 dropped the instruct")
  }

  @Test(.enabled(if: liveEnabled, skipReason))
  func designsOneVoiceSavesItAndFreesTheSlot() async throws {
    let plugin = try await makePlugin()
    let client = plugin.onceClient(apiKey: liveKey)
    let name = "SHO-live-test-\(UUID().uuidString.prefix(8))"

    let before = try await client.subscription().voiceSlotsUsed
    log("voice_slots_used before: \(String(describing: before))")
    let sample =
      "The tide is out and the lanterns are lit along the pier, so come and walk with me a while before the fog rolls in."
    #expect((100...150).contains(sample.count), "sample is \(sample.count) characters")

    var createdVoiceId: String?
    var failure: Error?
    do {
      let designer = plugin.designer(voiceName: name)
      let candidates = try await designer.design(
        VoiceDesignRequest(
          description: "A calm, warm older woman with a soft coastal accent", sampleText: sample))
      #expect(!candidates.isEmpty)
      let first = try #require(candidates.first)
      if let preview = await plugin.previewCache.preview(id: first.handle.identifier) {
        log("design preview media_type for pcm_24000: \(preview.mediaType)")
      }
      log("previews returned: \(candidates.count)")

      var asset = VoiceAsset(name: name, description: "live test")
      try await designer.save(first, into: &asset)
      createdVoiceId = asset.extensionFields(forEngine: "elevenlabs")?["voice_id"] as? String
      #expect(createdVoiceId != nil)
    } catch {
      failure = error
    }

    // Cleanup runs on success and failure alike.
    var deleteError: Error?
    if let id = createdVoiceId {
      do { try await client.deleteVoice(id) } catch { deleteError = error }
    } else {
      // Saved but not recorded (failure mid-save): find by the unique name.
      await client.invalidateVoiceCache()
      if let found = try? await client.voices(search: name, category: .generated),
        !found.voices.isEmpty
      {
        for voice in found.voices where voice.name == name {
          do { try await client.deleteVoice(voice.voiceId) } catch { deleteError = error }
        }
      }
    }
    let after = try await client.subscription().voiceSlotsUsed
    log("voice_slots_used after: \(String(describing: after))")

    if let failure { throw failure }
    if let deleteError { throw deleteError }
    #expect(
      after == before,
      "voice slot leaked: before \(String(describing: before)), after \(String(describing: after))")
  }
}
