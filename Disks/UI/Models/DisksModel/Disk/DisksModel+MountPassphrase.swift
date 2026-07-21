//
//  DisksModel+MountPassphrase.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/19/26.
//

import Foundation

extension URL {
  static let diskutil = Self(filePath: "/usr/sbin/diskutil", directoryHint: .notDirectory)
}

struct DisksModelMountPassphraseBadOutputError {
  let data: Data
  let underlyingError: any Error
}

struct DisksModelMountPassphraseError {
  let device: String
  let code: DisksModelMountPassphraseErrorCode
}

extension DisksModelMountPassphraseError: Error {}

enum DisksModelMountPassphraseErrorCode {
  case process(any Error),
       badOutput(DisksModelMountPassphraseBadOutputError),
       notSuccessful
}

private struct DisksModelMountPassphraseOutput {
  let success: Bool
}

extension DisksModelMountPassphraseOutput: Decodable {
  enum CodingKeys: String, CodingKey {
    case success = "Success"
  }
}

extension DisksModel {
  func mount(disk: DiskModel, passphrase: String) async throws(DisksModelMountPassphraseError) {
    try await self.mount(device: disk.device, passphrase: passphrase)
  }

  nonisolated private func mount(device: String, passphrase: String) async throws(DisksModelMountPassphraseError) {
    let data: Data

    do {
      data = try await self.process(
        executable: .diskutil,
        arguments: ["apfs", "unlockVolume", device, "-stdinpassphrase", "-plist"],
        data: passphrase.data(using: .utf8)!,
      )
    } catch {
      throw DisksModelMountPassphraseError(device: device, code: .process(error))
    }

    let output: DisksModelMountPassphraseOutput

    do {
      output = try PropertyListDecoder().decode(DisksModelMountPassphraseOutput.self, from: data)
    } catch {
      throw DisksModelMountPassphraseError(
        device: device,
        code: .badOutput(DisksModelMountPassphraseBadOutputError(data: data, underlyingError: error)),
      )
    }

    guard output.success else {
      throw DisksModelMountPassphraseError(device: device, code: .notSuccessful)
    }
  }
}
