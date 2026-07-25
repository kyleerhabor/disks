//
//  DisksModel+Rename.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/24/26.
//

import Foundation
import GRDB

enum DisksModelRenameDiskDriveErrorReason {
  case database(any Error)
}

struct DisksModelRenameDiskDriveError {
  let reason: DisksModelRenameDiskDriveErrorReason
}

extension DisksModelRenameDiskDriveError: Error {}

extension DisksModel {
  func rename(drive: RenameDiskDriveModel) async throws(DisksModelRenameDiskDriveError) {
    let serial = self.disks[drive.device]!.deviceSerial!
    try await self.rename(session: self.session!.session, device: drive.device, serial: serial, name: drive.name)
  }

  nonisolated private func rename(
    session: DASession,
    device: String,
    serial: String,
    name: String,
  ) async throws(DisksModelRenameDiskDriveError) {
    let connection: DatabasePool

    do {
      connection = try await databaseConnection()
    } catch {
      throw DisksModelRenameDiskDriveError(reason: .database(error))
    }

    do {
      try await connection.write { db in
        let name = name.isEmpty ? nil : name

        if let found = try DiskDriveRecord.fetchOne(db, key: [DiskDriveRecord.Columns.serial.name: serial]) {
          let drive = DiskDriveRecord(rowID: found.rowID, serial: nil, name: name)
          try drive.update(db, columns: [DiskDriveRecord.Columns.name])

          return
        }

        var drive = DiskDriveRecord(serial: serial, name: name)
        try drive.insert(db)
      }
    } catch {
      throw DisksModelRenameDiskDriveError(reason: .database(error))
    }
  }
}
