//
//  DisksModel+X.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/20/26.
//

import Foundation

private struct DisksModelWholeDeviceOutputEntryPartition {
  let deviceIdentifier: String
}

extension DisksModelWholeDeviceOutputEntryPartition: Decodable {
  enum CodingKeys: String, CodingKey {
    case deviceIdentifier = "DeviceIdentifier"
  }
}

private struct DisksModelWholeDeviceOutputEntryAPFSVolume {
  let deviceIdentifier: String
}

extension DisksModelWholeDeviceOutputEntryAPFSVolume: Decodable {
  enum CodingKeys: String, CodingKey {
    case deviceIdentifier = "DeviceIdentifier"
  }
}

private struct DisksModelWholeDeviceOutputEntryAPFSPhysicalStore {
  let deviceIdentifier: String
}

extension DisksModelWholeDeviceOutputEntryAPFSPhysicalStore: Decodable {
  enum CodingKeys: String, CodingKey {
    case deviceIdentifier = "DeviceIdentifier"
  }
}

private struct DisksModelWholeDeviceOutputEntry {
  let deviceIdentifier: String
  let partitions: [DisksModelWholeDeviceOutputEntryPartition]
  let apfsVolumes: [DisksModelWholeDeviceOutputEntryAPFSVolume]?
  let apfsPhysicalStores: [DisksModelWholeDeviceOutputEntryAPFSPhysicalStore]?
}

extension DisksModelWholeDeviceOutputEntry: Decodable {
  enum CodingKeys: String, CodingKey {
    case deviceIdentifier = "DeviceIdentifier"
    case partitions = "Partitions"
    case apfsVolumes = "APFSVolumes"
    case apfsPhysicalStores = "APFSPhysicalStores"
  }
}

private struct DisksModelWholeDeviceOutput {
  let entries: [DisksModelWholeDeviceOutputEntry]
}

extension DisksModelWholeDeviceOutput: Decodable {
  enum CodingKeys: String, CodingKey {
    case entries = "AllDisksAndPartitions"
  }
}

enum DisksModelWholeDeviceErrorCode {
  case process(any Error),
       decode(any Error)
}

struct DisksModelWholeDeviceError {
  let code: DisksModelWholeDeviceErrorCode
}

extension DisksModelWholeDeviceError: Error {}

extension DisksModel {
  nonisolated func wholeDevice(name: String) async throws(DisksModelWholeDeviceError) -> String {
    let data: Data

    do {
      data = try await self.process(executable: .diskutil, arguments: ["list", "-plist"], data: Data())
    } catch {
      throw DisksModelWholeDeviceError(code: .process(error))
    }

    let decoder = PropertyListDecoder()
    let output: DisksModelWholeDeviceOutput

    do {
      output = try decoder.decode(DisksModelWholeDeviceOutput.self, from: data)
    } catch {
      throw DisksModelWholeDeviceError(code: .decode(error))
    }

    var partitionToWhole = [String: String]()
    var volumeToWhole = [String: String]()

    for entry in output.entries {
      for partition in entry.partitions {
        partitionToWhole[partition.deviceIdentifier] = entry.deviceIdentifier
      }

      if let stores = entry.apfsPhysicalStores,
         let volumes = entry.apfsVolumes {
        let store = stores.first!
        let whole = partitionToWhole[store.deviceIdentifier]!

        for volume in volumes {
          volumeToWhole[volume.deviceIdentifier] = whole
        }
      }
    }

    let name = volumeToWhole[name]!

    return name
  }
}
