//
//  DisksModel+DriveEject.swift
//  Disks
//
//  Created by Kyle Erhabor on 8/2/26.
//

import Foundation

enum DisksModelEjectDriveErrorReason {
  case ejectDisk(EjectDiskError)
}

struct DisksModelEjectDriveError {
  let device: String
  let reason: DisksModelEjectDriveErrorReason
}

extension DisksModelEjectDriveError: Error {}

extension DisksModel {
  func eject(drive: DisksDriveModel) async throws(DisksModelEjectDriveError) {
    let device = drive.device

    guard let disk = DADiskCreateFromBSDName(nil, self.session!.session, device) else {
      return
    }

    do {
      try await Disks.eject(disk: disk)
    } catch {
      throw DisksModelEjectDriveError(device: device, reason: .ejectDisk(error))
    }
  }
}
