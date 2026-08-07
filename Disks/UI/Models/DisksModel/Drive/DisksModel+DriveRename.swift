//
//  DisksModel+DriveRename.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/24/26.
//

import Foundation
import GRDB

enum DisksModelRenameDriveErrorReason {
  case database(any Error)
}

struct DisksModelRenameDriveError {
  let reason: DisksModelRenameDriveErrorReason
}

extension DisksModelRenameDriveError: Error {}

struct DisksDriveRenameDriveContinuationDiskDriveSource {
  let serial: String
}

enum DisksDriveRenameDriveContinuationSource {
  case disk(DisksDriveRenameDriveContinuationDiskDriveSource)
}

struct DisksDriveRenameDriveContinuation {
  let source: DisksDriveRenameDriveContinuationSource
}

extension DisksModel {
  func rename(resuming drive: DisksDriveRenameDriveContinuation, name: String) async throws(DisksModelRenameDriveError) {
    try await self.rename(source: drive.source, name: name)
  }

  nonisolated private func rename(
    source: DisksDriveRenameDriveContinuationSource,
    name: String,
  ) async throws(DisksModelRenameDriveError) {
    let connection: DatabasePool

    do {
      connection = try await databaseConnection()
    } catch {
      throw DisksModelRenameDriveError(reason: .database(error))
    }

    do {
      try await connection.write { db in
        switch source {
          case let .disk(source):
            if let existing = try DiskDriveRecord.fetchOne(db, key: [DiskDriveRecord.Columns.serial.name: source.serial]) {
              let drive = DiskDriveRecord(rowID: existing.rowID, serial: nil, name: name)
              try drive.update(db, columns: [DiskDriveRecord.Columns.name])

              return
            }

            var drive = DiskDriveRecord(serial: source.serial, name: name)
            try drive.insert(db)
        }
      }
    } catch {
      throw DisksModelRenameDriveError(reason: .database(error))
    }
  }
}
