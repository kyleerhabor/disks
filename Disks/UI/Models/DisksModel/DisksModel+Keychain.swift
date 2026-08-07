//
//  DisksModel+Keychain.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/29/26.
//

import Foundation
import LocalAuthentication

struct DisksModelKeychainPasswordDatabaseError {
  let status: OSStatus
}

enum DisksModelKeychainPasswordErrorReason {
  case database(DisksModelKeychainPasswordDatabaseError),
       badOutput
}

struct DisksModelKeychainPasswordError {
  let reason: DisksModelKeychainPasswordErrorReason
}

extension DisksModelKeychainPasswordError: Error {}

extension DisksModel {
  nonisolated static let diskPasswordKeychainService = "\(Bundle.appID).disk-password"
  nonisolated static let diskImagePasswordKeychainService = "\(Bundle.appID).disk-image-password"

  nonisolated static func loadKeychainPassword(
    service: String,
    account: String,
    authentication: LAContext,
  ) throws(DisksModelKeychainPasswordError) -> String {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecUseAuthenticationContext: authentication,
    ]

    var result: CFTypeRef!
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess else {
      throw DisksModelKeychainPasswordError(reason: .database(DisksModelKeychainPasswordDatabaseError(status: status)))
    }

    let data = result as! Data

    guard let password = String(data: data, encoding: .utf8) else {
      throw DisksModelKeychainPasswordError(reason: .badOutput)
    }

    return password
  }

  nonisolated static func storeKeychainPassword(
    service: String,
    account: String,
    password: String,
  ) throws(DisksModelKeychainPasswordError) {
    let value = password.data(using: .utf8)!
    let addQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
      kSecValueData: value,
    ]

    let updateQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecMatchLimit: kSecMatchLimitOne,
    ]

    let updateAttributes: [CFString: Any] = [kSecValueData: value]
    let status = upsertKeychainItem(
      addQuery: addQuery as CFDictionary,
      updateQuery: updateQuery as CFDictionary,
      updateAttributes: updateAttributes as CFDictionary,
    )

    guard status == errSecSuccess else {
      throw DisksModelKeychainPasswordError(reason: .database(DisksModelKeychainPasswordDatabaseError(status: status)))
    }
  }
}
