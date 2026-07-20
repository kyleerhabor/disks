//
//  DisksModel+DiskImageLoadPassword.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/19/26.
//

import Foundation
import GRDB
import LocalAuthentication

struct DisksModelDiskLoadPasswordDatabaseItemNotFoundError {
  let uuid: UUID
}

extension DisksModelDiskLoadPasswordDatabaseItemNotFoundError: Error {}

struct DisksModelDiskLoadPasswordKeychainError {
  let status: OSStatus
}

extension DisksModelDiskLoadPasswordKeychainError: Error {}

struct DisksModelDiskLoadPasswordBadKeychainDataError {
  let data: Data
}

extension DisksModelDiskLoadPasswordBadKeychainDataError: Error {}

enum DisksModelDiskLoadPasswordErrorCode {
  case database(any Error),
       keychain(any Error),
       badKeychainData(DisksModelDiskLoadPasswordBadKeychainDataError)
}

extension DisksModelDiskLoadPasswordErrorCode: Error {}

struct DisksModelDiskLoadPasswordError {
  let code: DisksModelDiskLoadPasswordErrorCode
}

extension DisksModelDiskLoadPasswordError: Error {}


extension DisksModel {
  func loadPassword(disk: DiskModel) async throws(DisksModelDiskLoadPasswordError) -> String {
    try await self.loadPassword(uuid: disk.uuid, name: disk.name)
  }

  nonisolated private func loadPassword(uuid: UUID, name: String) async throws(DisksModelDiskLoadPasswordError) -> String {
    let connection: DatabasePool

    do {
      connection = try await databaseConnection()
    } catch {
      throw DisksModelDiskLoadPasswordError(code: .database(error))
    }

    let disk: DiskRecord?

    do {
      disk = try await connection.read { db in
        try DiskRecord.fetchOne(db, key: [DiskRecord.Columns.uuid.name: uuid])
      }
    } catch {
      throw DisksModelDiskLoadPasswordError(code: .database(error))
    }

    guard let disk else {
      throw DisksModelDiskLoadPasswordError(code: .database(DisksModelDiskLoadPasswordDatabaseItemNotFoundError(uuid: uuid)))
    }

    let account = disk.id!.uuidString
    let context = LAContext()

    do {
      try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "unlock the disk “\(name)”")
    } catch {
      throw DisksModelDiskLoadPasswordError(code: .keychain(error))
    }

    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: Self.diskPasswordService,
      kSecAttrAccount: account,
      kSecUseAuthenticationContext: context,
      kSecUseDataProtectionKeychain: true,
      kSecReturnData: true,
    ]

    var result: CFTypeRef!
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess else {
      throw DisksModelDiskLoadPasswordError(code: .keychain(DisksModelDiskLoadPasswordKeychainError(status: status)))
    }

    let data = result as! Data

    guard let password = String(data: data, encoding: .utf8) else {
      throw DisksModelDiskLoadPasswordError(code: .badKeychainData(DisksModelDiskLoadPasswordBadKeychainDataError(data: data)))
    }

    return password
  }
}
