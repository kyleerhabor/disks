//
//  DisksModel+DiskImageStorePassword.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/19/26.
//

import Foundation
import GRDB
import Security

struct DisksModelDiskStorePasswordKeychainError {
  let status: OSStatus
}

extension DisksModelDiskStorePasswordKeychainError: Error {}

enum DisksModelDiskStorePasswordErrorCode {
  case database(any Error),
       keychain(any Error)
}

extension DisksModelDiskStorePasswordErrorCode: Error {}

struct DisksModelDiskStorePasswordError {
  let code: DisksModelDiskStorePasswordErrorCode
}

extension DisksModelDiskStorePasswordError: Error {}

extension DisksModel {
  func store(disk: DiskModel, password: String) async throws(DisksModelDiskStorePasswordError) {
    try await self.store(uuid: disk.uuid, password: password)
  }

  nonisolated private func store(uuid: UUID, password: String) async throws(DisksModelDiskStorePasswordError) {
    let connection: DatabasePool

    do {
      connection = try await databaseConnection()
    } catch {
      throw DisksModelDiskStorePasswordError(code: .database(error))
    }

    let disk: DiskRecord

    do {
      disk = try await connection.write { db in
        if let disk = try DiskRecord.filter(DiskRecord.Columns.uuid == uuid).fetchOne(db) {
          return disk
        }

        var disk = DiskRecord(id: UUID(), uuid: uuid)
        try disk.insert(db)

        return disk
      }
    } catch {
      throw DisksModelDiskStorePasswordError(code: .database(error))
    }

    var error: Unmanaged<CFError>?
    let secAccessControl = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenUnlocked,
      .userPresence,
      &error,
    )

    if let error {
      throw DisksModelDiskStorePasswordError(code: .keychain(error.takeRetainedValue()))
    }

    let accessControl = secAccessControl!
    let account = disk.id!.uuidString
    let value = password.data(using: .utf8)!
    let addQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: Self.diskPasswordService,
      kSecAttrAccount: account,
      kSecValueData: value,
      kSecUseDataProtectionKeychain: true,
      kSecAttrAccessControl: accessControl,
    ]

    let updateQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: Self.diskPasswordService,
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
      throw DisksModelDiskStorePasswordError(code: .keychain(DisksModelDiskStorePasswordKeychainError(status: status)))
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
