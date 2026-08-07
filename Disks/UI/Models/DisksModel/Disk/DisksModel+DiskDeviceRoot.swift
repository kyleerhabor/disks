//
//  DisksModel+DiskDeviceRoot.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/28/26.
//

import Foundation

private struct DiskDeviceRootProcessEntryPartitionOutput {
  let deviceIdentifier: String
}

extension DiskDeviceRootProcessEntryPartitionOutput: Decodable {
  enum CodingKeys: String, CodingKey {
    case deviceIdentifier = "DeviceIdentifier"
  }
}

private struct DiskDeviceRootProcessEntryAPFSVolumeProcessOutput {
  let deviceIdentifier: String
}

extension DiskDeviceRootProcessEntryAPFSVolumeProcessOutput: Decodable {
  enum CodingKeys: String, CodingKey {
    case deviceIdentifier = "DeviceIdentifier"
  }
}

private struct DiskDeviceRootProcessEntryAPFSPhysicalStoreOutput {
  let deviceIdentifier: String
}

extension DiskDeviceRootProcessEntryAPFSPhysicalStoreOutput: Decodable {
  enum CodingKeys: String, CodingKey {
    case deviceIdentifier = "DeviceIdentifier"
  }
}

private enum DiskDeviceRootEntryContentProcessOutput {
  case guidPartitionScheme,
       appleAPFSContainer,
       other
}

extension DiskDeviceRootEntryContentProcessOutput: Decodable {
  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)

    switch rawValue {
      case "GUID_partition_scheme":
        self = .guidPartitionScheme
      case "Apple_APFS_Container":
        self = .appleAPFSContainer
      default:
        self = .other
    }
  }
}

private struct DiskDeviceRootEntryProcessOutput {
  let content: DiskDeviceRootEntryContentProcessOutput
  let deviceIdentifier: String
  let partitions: [DiskDeviceRootProcessEntryPartitionOutput]
  let apfsVolumes: [DiskDeviceRootProcessEntryAPFSVolumeProcessOutput]?
  let apfsPhysicalStores: [DiskDeviceRootProcessEntryAPFSPhysicalStoreOutput]?
}

extension DiskDeviceRootEntryProcessOutput: Decodable {
  enum CodingKeys: String, CodingKey {
    case content = "Content",
         deviceIdentifier = "DeviceIdentifier",
         partitions = "Partitions",
         apfsVolumes = "APFSVolumes",
         apfsPhysicalStores = "APFSPhysicalStores"
  }
}

private struct DiskDeviceRootProcessOutput {
  let entries: [DiskDeviceRootEntryProcessOutput]
}

extension DiskDeviceRootProcessOutput: Decodable {
  enum CodingKeys: String, CodingKey {
    case entries = "AllDisksAndPartitions"
  }
}

struct DisksModelDiskDeviceRootBadProcessExitError {
  let status: Int32
}

enum DisksModelDiskDeviceRootErrorReason {
  case process(any Error),
       badProcessExit(DisksModelDiskDeviceRootBadProcessExitError),
       badProcessOutput,
       notFound
}

struct DisksModelDiskDeviceRootError {
  let reason: DisksModelDiskDeviceRootErrorReason
}

extension DisksModelDiskDeviceRootError: Error {}

extension DisksModel {
  nonisolated func rootDevice(of device: String) async throws(DisksModelDiskDeviceRootError) -> String {
    let output: ProcessOutput

    do {
      output = try await Process.run(executable: .diskutil, arguments: ["list", "-plist"])
    } catch {
      throw DisksModelDiskDeviceRootError(reason: .process(error))
    }

    guard output.exitStatus == 0 else {
      throw DisksModelDiskDeviceRootError(
        reason: .badProcessExit(DisksModelDiskDeviceRootBadProcessExitError(status: output.exitStatus)),
      )
    }

    let decoder = PropertyListDecoder()
    let decoded: DiskDeviceRootProcessOutput

    do {
      decoded = try decoder.decode(DiskDeviceRootProcessOutput.self, from: output.output!)
    } catch {
      throw DisksModelDiskDeviceRootError(reason: .badProcessOutput)
    }

    var roots = [String: String]()

    for entry in decoded.entries {
      var root = entry.deviceIdentifier

      switch entry.content {
        case .guidPartitionScheme:
          for partition in entry.partitions {
            roots[partition.deviceIdentifier] = root
          }
        case .appleAPFSContainer:
          let store = entry.apfsPhysicalStores!.first!
          let volumes = entry.apfsVolumes!
          root = roots[store.deviceIdentifier]!

          for volume in volumes {
            roots[volume.deviceIdentifier] = root
          }
        case .other:
          // This should make non-bare content types fail with not found.
          guard entry.partitions.isEmpty else {
            continue
          }
      }

      roots[entry.deviceIdentifier] = root
    }

    guard let name = roots[device] else {
      // I believe this is necessary for other file systems.
      throw DisksModelDiskDeviceRootError(reason: .notFound)
    }

    return name
  }
}
