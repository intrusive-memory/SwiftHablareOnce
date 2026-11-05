//
//  LegacyKeychain.swift
//  SwiftHablareOnce
//
//  Reads the Keychain item that SwiftHablareOnce 0.1.0 (via SwiftHablare 6.x
//  `KeychainManager`) wrote: a generic password with account "elevenlabs-api-key",
//  no service and no access group. Injectable so tests never touch the real Keychain.
//

import Foundation
import Security
import SwiftHablare

/// Read access to the pre-7.0 ElevenLabs key. Implementations must never log the key.
public protocol LegacyKeychainReading: Sendable {
  /// The legacy key, or `nil` when none is stored.
  func legacyAPIKey() -> String?
}

/// Reads the real login Keychain.
public struct SystemLegacyKeychain: LegacyKeychainReading {
  public static let account = "elevenlabs-api-key"

  public init() {}

  public func legacyAPIKey() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: Self.account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else { return nil }
    let key = String(decoding: data, as: UTF8.self)
    return key.isEmpty ? nil : key
  }
}

/// Copies the legacy key into Hablare's store at most once per instance (OQ-5).
///
/// The legacy item is left in place (a copy, not a move). The legacy Keychain is consulted
/// only when Hablare's store has no key, and only on the first such lookup: a later removal
/// of the key through Hablare does not resurrect the legacy value within this instance.
final class LegacyKeyMigrator: @unchecked Sendable {
  private let legacy: any LegacyKeychainReading
  private let lock = NSLock()
  private var attempted = false

  init(legacy: any LegacyKeychainReading) {
    self.legacy = legacy
  }

  /// The key from `keys`, falling back (once) to the legacy item, which is then copied
  /// into `keys` under `account`.
  func resolve(in keys: any APIKeyStoring, account: String) -> String? {
    if let key = keys.apiKey(for: account) { return key }
    let shouldTry: Bool = lock.withLock {
      if attempted { return false }
      attempted = true
      return true
    }
    guard shouldTry, let key = legacy.legacyAPIKey() else { return nil }
    // A failed write must not lose the key for this session; the error carries no key.
    try? keys.setAPIKey(key, for: account)
    return key
  }
}
