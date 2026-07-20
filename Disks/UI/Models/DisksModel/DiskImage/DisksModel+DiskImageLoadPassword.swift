//
//  DisksModel+DiskImageLoadPassword.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/19/26.
//

import Foundation
import GRDB
import LocalAuthentication

struct DisksModelImageLoadPasswordDatabaseItemNotFoundError {
  let uuid: UUID
}

extension DisksModelImageLoadPasswordDatabaseItemNotFoundError: Error {}

struct DisksModelImageLoadPasswordKeychainError {
  let status: OSStatus
}

extension DisksModelImageLoadPasswordKeychainError: Error {}

struct DisksModelImageLoadPasswordBadKeychainDataError {
  let data: Data
}

extension DisksModelImageLoadPasswordBadKeychainDataError: Error {}

enum DisksModelImageLoadPasswordErrorCode {
  case database(any Error),
       keychain(any Error),
       badKeychainData(DisksModelImageLoadPasswordBadKeychainDataError)
}

extension DisksModelImageLoadPasswordErrorCode: Error {}

struct DisksModelImageLoadPasswordError {
  let code: DisksModelImageLoadPasswordErrorCode
}

extension DisksModelImageLoadPasswordError: Error {}


extension DisksModel {
  func loadPassword(image: DiskImageModel) async throws(DisksModelImageLoadPasswordError) -> String {
    try await self.loadPassword(uuid: image.uuid, name: image.name)
  }

  nonisolated private func loadPassword(uuid: UUID, name: String) async throws(DisksModelImageLoadPasswordError) -> String {
    let connection: DatabasePool

    do {
      connection = try await databaseConnection()
    } catch {
      throw DisksModelImageLoadPasswordError(code: .database(error))
    }

    let image: DiskImageRecord?

    do {
      image = try await connection.read { db in
        try DiskImageRecord.fetchOne(db, key: [DiskImageRecord.Columns.uuid.name: uuid])
      }
    } catch {
      throw DisksModelImageLoadPasswordError(code: .database(error))
    }

    guard let image else {
      throw DisksModelImageLoadPasswordError(code: .database(DisksModelImageLoadPasswordDatabaseItemNotFoundError(uuid: uuid)))
    }

    let account = image.id!.uuidString
    let context = LAContext()

    do {
      try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "unlock the disk image “\(name)”")
    } catch {
      throw DisksModelImageLoadPasswordError(code: .keychain(error))
    }

    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: Self.diskImagePasswordService,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecUseAuthenticationContext: context,
    ]

    var result: CFTypeRef!
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess else {
      throw DisksModelImageLoadPasswordError(code: .keychain(DisksModelImageLoadPasswordKeychainError(status: status)))
    }

    let data = result as! Data

    guard let password = String(data: data, encoding: .utf8) else {
      throw DisksModelImageLoadPasswordError(
        code: .badKeychainData(DisksModelImageLoadPasswordBadKeychainDataError(data: data)),
      )
    }

    return password
  }
}
