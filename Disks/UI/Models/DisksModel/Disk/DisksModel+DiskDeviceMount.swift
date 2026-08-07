//
//  DisksModel+DiskDeviceMount.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/29/26.
//

import Foundation

private struct MountDiskDeviceProcessOutput {
  let success: Bool
}

extension MountDiskDeviceProcessOutput: Decodable {
  enum CodingKeys: String, CodingKey {
    case success = "Success"
  }
}

struct DisksModelMountDiskDeviceBadProcessExitError {
  let status: Int32
}

enum DisksModelMountDiskDeviceErrorReason {
  case process(any Error),
       badProcessExit(DisksModelMountDiskDeviceBadProcessExitError),
       badProcessOutput(any Error),
       notSuccessful
}

struct DisksModelMountDiskDeviceError {
  let reason: DisksModelMountDiskDeviceErrorReason
}

extension DisksModelMountDiskDeviceError: Error {}

extension DisksModel {
  nonisolated static func mount(device: String, password: String) async throws(DisksModelMountDiskDeviceError) {
    let output: ProcessOutput

    do {
      output = try await Process.run(
        executable: .diskutil,
        arguments: ["apfs", "unlockVolume", device, "-stdinpassphrase", "-plist"],
        input: password.data(using: .utf8)!,
      )
    } catch {
      throw DisksModelMountDiskDeviceError(reason: .process(error))
    }

    guard output.exitStatus == 0 else {
      throw DisksModelMountDiskDeviceError(
        reason: .badProcessExit(DisksModelMountDiskDeviceBadProcessExitError(status: output.exitStatus)),
      )
    }

    let decoder = PropertyListDecoder()
    let decoded: MountDiskDeviceProcessOutput

    do {
      decoded = try decoder.decode(MountDiskDeviceProcessOutput.self, from: output.output!)
    } catch {
      throw DisksModelMountDiskDeviceError(reason: .badProcessOutput(error))
    }

    guard decoded.success else {
      throw DisksModelMountDiskDeviceError(reason: .notSuccessful)
    }
  }
}
