//
//  ElevenLabsConformanceTests.swift
//  SwiftHablareOnceTests
//
//  Sortie 12. Runs Hablare's `ConformanceKit` against `ElevenLabsPlugin` with no network.
//  The kit builds the plugin itself (`P(context:)`), so HTTP is mocked at the URL loading
//  layer: a `URLProtocol` answers every request SwiftOnce sends through `URLSession.shared`.
//

import Foundation
import SwiftHablare
import SwiftHablareTesting
import Testing

@testable import SwiftHablareOnce

/// Answers every request locally; nothing reaches the network.
private final class MockElevenLabsProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let url = request.url!
    let body: Data
    var headers = ["Content-Type": "application/json"]
    if url.path == "/v1/user/subscription" {
      body = Data(
        #"{"tier":"creator","status":"active","character_count":0,"character_limit":10000000,"voice_limit":30,"voice_slots_used":1}"#
          .utf8)
    } else if url.path.hasPrefix("/v1/text-to-speech/") {
      headers["Content-Type"] = "audio/pcm"
      // 0.25 s of 24 kHz 16-bit mono PCM (a quiet ramp).
      var pcm = Data()
      for i in 0..<6_000 {
        var sample = Int16(truncatingIfNeeded: (i % 100) - 50).littleEndian
        withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
      }
      body = pcm
    } else {
      body = Data("{}".utf8)
    }
    let response = HTTPURLResponse(
      url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite(.serialized) struct ElevenLabsConformanceTests {

  @Test func conformanceKitPasses() async throws {
    URLProtocol.registerClass(MockElevenLabsProtocol.self)
    defer { URLProtocol.unregisterClass(MockElevenLabsProtocol.self) }

    let fakeKey = "sk_conformance_planted_key_9f8e7d6c5b4a"
    let keys = InMemoryAPIKeyStore(keys: [ElevenLabsPlugin.keyAccount: fakeKey])
    let context = PluginContext(keys: keys, registry: PluginRegistry(plugins: []))

    let report = await ConformanceKit.run(
      ElevenLabsPlugin.self, context: context,
      voice: .catalog(pluginId: "elevenlabs", voiceId: "voice123"),
      mode: .full, secrets: [fakeKey])

    #expect(report.failures.isEmpty, "\(report.summary)")
    #expect(report.passedChecks.count >= 6, "\(report.summary)")
    #expect(report.result(for: .secrecyStatus)?.outcome == .passed, "\(report.summary)")
    #expect(report.result(for: .secrecyErrors)?.outcome == .passed, "\(report.summary)")
  }
}
