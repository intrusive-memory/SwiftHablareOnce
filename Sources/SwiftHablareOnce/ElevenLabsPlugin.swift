//
//  ElevenLabsPlugin.swift
//  SwiftHablareOnce
//
//  ElevenLabs on SwiftHablare 7 (EL-1). Skeleton: identity, credentials, models, settings,
//  status and the quota check. The synthesizer and designer roles arrive in later sorties.
//  Reads no UserDefaults: model and voice settings come only from request settings and
//  `PluginConfiguration` (EL-1.2).
//

import Foundation
import SwiftHablare
import SwiftOnce

public final class ElevenLabsPlugin: HablarePlugin {
  public static let id = "elevenlabs"
  public static let displayName = "ElevenLabs"
  public static let kind: PluginKind = .cloud
  public static let credentials: [CredentialRequirement] = [.elevenLabs]
  public static let models: [ModelDescriptor] = ElevenLabsModels.descriptors
  public static let settingsSchema: SettingsSchema = ElevenLabsModels.settingsSchema

  /// The store id the key lives under (`CredentialRequirement.elevenLabs.keychainAccount`).
  static let keyAccount = CredentialRequirement.elevenLabs.keychainAccount

  let keys: any APIKeyStoring
  let httpClient: (any HTTPClient)?
  let onceConfiguration: SwiftOnceConfiguration
  private let migrator: LegacyKeyMigrator
  private let subscriptionCache = SubscriptionCache()

  public convenience init(context: PluginContext) async throws {
    try await self.init(context: context, legacyKeychain: SystemLegacyKeychain())
  }

  /// - Parameters:
  ///   - legacyKeychain: source of the pre-7.0 key; inject a fake in tests.
  ///   - httpClient: SwiftOnce transport; `nil` uses `URLSession.shared`.
  public init(
    context: PluginContext,
    legacyKeychain: any LegacyKeychainReading,
    httpClient: (any HTTPClient)? = nil,
    onceConfiguration: SwiftOnceConfiguration = SwiftOnceConfiguration(
      defaultModel: Model(ElevenLabsModels.defaultModelId))
  ) async throws {
    // Reject unknown plugin-wide keys up front, naming the key.
    _ = try context.configuration.validated(against: Self.settingsSchema)
    self.keys = context.keys
    self.httpClient = httpClient
    self.onceConfiguration = onceConfiguration
    self.migrator = LegacyKeyMigrator(legacy: legacyKeychain)
  }

  // MARK: Credentials

  /// The API key: Hablare's store first, then (once) the legacy Keychain item, which is
  /// copied into Hablare's store. Internal so the key never appears in public API.
  func resolveAPIKey() -> String? {
    migrator.resolve(in: keys, account: Self.keyAccount)
  }

  // MARK: Status and quota

  public func status() async -> PluginStatus {
    guard resolveAPIKey() != nil else { return Self.missingCredentialStatus }
    return .ready
  }

  /// Status for a request of `characters` characters on `model`: `.needsCredential` with no
  /// key, `.unavailable(reason: "quota")` when remaining credits are below
  /// ``estimateCost(characters:model:)``, otherwise `.ready`. The subscription is fetched
  /// once and cached for the life of this plugin instance. If it cannot be fetched, the
  /// check does not block (the request itself reports `quotaExceeded`).
  public func status(
    estimatingCharacters characters: Int,
    model: String = ElevenLabsModels.defaultModelId
  ) async -> PluginStatus {
    guard let key = resolveAPIKey() else { return Self.missingCredentialStatus }
    let estimate = Self.estimateCost(characters: characters, model: model)
    guard let remaining = await remainingCredits(apiKey: key) else { return .ready }
    return remaining < estimate ? .unavailable(reason: "quota") : .ready
  }

  /// Characters x the model's credit factor, rounded up.
  public static func estimateCost(characters: Int, model: String) -> Int {
    Int((Double(max(characters, 0)) * ElevenLabsModels.costFactor(forModel: model)).rounded(.up))
  }

  public func estimateCost(characters: Int, model: String = ElevenLabsModels.defaultModelId) -> Int
  {
    Self.estimateCost(characters: characters, model: model)
  }

  /// Remaining credits from `subscription()`, cached per plugin instance. `nil` when there is
  /// no key or the subscription cannot be read.
  public func remainingCredits() async -> Int? {
    guard let key = resolveAPIKey() else { return nil }
    return await remainingCredits(apiKey: key)
  }

  /// Drops the cached subscription so the next check re-reads it.
  public func invalidateSubscriptionCache() async {
    await subscriptionCache.invalidate()
  }

  private func remainingCredits(apiKey: String) async -> Int? {
    let client = SwiftOnce(
      apiKey: apiKey, configuration: onceConfiguration, httpClient: httpClient)
    return await subscriptionCache.remaining { try await client.subscription() }
  }

  private static var missingCredentialStatus: PluginStatus {
    .needsCredential(envVar: CredentialRequirement.elevenLabs.primaryEnvironmentVariable)
  }
}

/// Fetches the subscription once per plugin instance (until invalidated).
actor SubscriptionCache {
  private var cached: Subscription?

  func remaining(fetch: @Sendable () async throws -> Subscription) async -> Int? {
    if let cached { return cached.charactersRemaining }
    guard let fetched = try? await fetch() else { return nil }
    cached = fetched
    return fetched.charactersRemaining
  }

  func invalidate() { cached = nil }
}
