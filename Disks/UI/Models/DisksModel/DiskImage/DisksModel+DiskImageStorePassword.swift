//
//  DisksModel+DiskImageStorePassword.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/19/26.
//

import Foundation
import GRDB
import Security

struct DisksModelImageStorePasswordKeychainError {
  let status: OSStatus
}

extension DisksModelImageStorePasswordKeychainError: Error {}

enum DisksModelImageStorePasswordErrorCode {
  case database(any Error),
       keychain(any Error)
}

extension DisksModelImageStorePasswordErrorCode: Error {}

struct DisksModelImageStorePasswordError {
  let code: DisksModelImageStorePasswordErrorCode
}

extension DisksModelImageStorePasswordError: Error {}

extension DisksModel {
  func store(image: DiskImageModel, password: String) async throws(DisksModelImageStorePasswordError) {
    try await self.store(uuid: image.uuid, password: password)
  }

  nonisolated private func store(uuid: UUID, password: String) async throws(DisksModelImageStorePasswordError) {
    let connection: DatabasePool

    do {
      connection = try await databaseConnection()
    } catch {
      throw DisksModelImageStorePasswordError(code: .database(error))
    }

    let image: DiskImageRecord

    do {
      image = try await connection.write { db in
        if let image = try DiskImageRecord.filter(DiskImageRecord.Columns.uuid == uuid).fetchOne(db) {
          return image
        }

        var image = DiskImageRecord(id: UUID(), uuid: uuid)
        try image.insert(db)

        return image
      }
    } catch {
      throw DisksModelImageStorePasswordError(code: .database(error))
    }

    var error: Unmanaged<CFError>?
    let secAccessControl = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenUnlocked,
      .userPresence,
      &error,
    )

    if let error {
      throw DisksModelImageStorePasswordError(code: .keychain(error.takeRetainedValue()))
    }

    let accessControl = secAccessControl!
    let account = image.id!.uuidString
    let value = password.data(using: .utf8)!
    let addQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: Self.diskImagePasswordService,
      kSecAttrAccount: account,
      kSecValueData: value,
      kSecUseDataProtectionKeychain: true,
      kSecAttrAccessControl: accessControl,
    ]

    let updateQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: Self.diskImagePasswordService,
      kSecAttrAccount: account,
      kSecMatchLimit: kSecMatchLimitOne,
      kSecUseDataProtectionKeychain: true,
    ]

    let updateAttributes: [CFString: Any] = [
      kSecValueData: value,
    ]

    let status = self.upsert(
      addQuery: addQuery as CFDictionary,
      updateQuery: updateQuery as CFDictionary,
      updateAttributes: updateAttributes as CFDictionary,
    )

    guard status == errSecSuccess else {
      throw DisksModelImageStorePasswordError(code: .keychain(DisksModelImageStorePasswordKeychainError(status: status)))
    }
  }

  nonisolated private func upsert(
    addQuery: CFDictionary,
    updateQuery: CFDictionary,
    updateAttributes: CFDictionary,
  ) -> OSStatus {
    let addStatus = SecItemAdd(addQuery, nil)

    guard addStatus == errSecDuplicateItem else {
      return addStatus
    }

    let updateStatus = SecItemUpdate(updateQuery, updateAttributes)

    return updateStatus
  }
}
