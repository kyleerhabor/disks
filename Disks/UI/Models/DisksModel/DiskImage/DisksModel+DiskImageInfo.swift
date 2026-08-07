//
//  DisksModel+DiskImageInfo.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/31/26.
//

import Foundation
import System

private struct InfoProcessOutput {
  let encrypted: Bool
  let uuid: UUID?
}

extension InfoProcessOutput: Decodable {}

struct DisksModelDiskImageInfoBadProcessExitError {
  let status: Int32
}

enum DisksModelDiskImageInfoErrorReason {
  case process(any Error),
       badProcessExit(DisksModelDiskImageInfoBadProcessExitError),
       badProcessOutput
}

struct DisksModelDiskImageInfoError {
  let reason: DisksModelDiskImageInfoErrorReason
}

extension DisksModelDiskImageInfoError: Error {}

struct DisksModelDiskImageInfo {
  let id: UUID?
  let isEncrypted: Bool
}

extension DisksModel {
  func diskImageInfo(path: FilePath) async throws(DisksModelDiskImageInfoError) -> DisksModelDiskImageInfo {
    let output: ProcessOutput

    do {
      output = try await Process.run(executable: .hdiutil, arguments: ["isencrypted", path.string, "-plist"])
    } catch {
      throw DisksModelDiskImageInfoError(reason: .process(error))
    }

    guard output.exitStatus == 0 else {
      throw DisksModelDiskImageInfoError(
        reason: .badProcessExit(DisksModelDiskImageInfoBadProcessExitError(status: output.exitStatus)),
      )
    }

    let decoder = PropertyListDecoder()
    let decoded: InfoProcessOutput

    do {
      decoded = try decoder.decode(InfoProcessOutput.self, from: output.output!)
    } catch {
      throw DisksModelDiskImageInfoError(reason: .badProcessOutput)
    }

    let info = DisksModelDiskImageInfo(id: decoded.uuid, isEncrypted: decoded.encrypted)

    return info
  }
}
