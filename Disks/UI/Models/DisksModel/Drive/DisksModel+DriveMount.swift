//
//  DisksModel+DriveMount.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/27/26.
//

import Foundation
import GRDB
import LocalAuthentication

private struct DriveMounterDisk {
  // MARK: Disks
  let store: DisksModelDisk

  // MARK: Disk
  let disk: DisksDriveDiskModel
}

private struct DriveMounterItem {
  let disk: DriveMounterDisk
  let hasKeychainPassword: Bool
  let keychainPasswordAccount: String?
}

private struct DriveMounter: DisksModelMounter {
  let model: DisksModel
  let drive: DisksDriveModel
  let disks: [DriveMounterDisk]

  // MARK: Disk Arbitration
  let session: DASession

  // MARK: Database
  let connection: DatabasePool

  // MARK: -
  private let authentication: LAContext
  private let shouldClearKeychainPassword: Bool
  private let currentItem: DriveMounterItem?
  private let remainingItems: [DriveMounterItem]?

  init(
    _ model: DisksModel,
    drive: DisksDriveModel,
    disks: [DriveMounterDisk],
    session: DASession,
    connection: DatabasePool,
  ) {
    self.init(
      model,
      drive: drive,
      disks: disks,
      session: session,
      connection: connection,
      authentication: LAContext(),
      shouldClearKeychainPassword: false,
      currentItem: nil,
      remainingItems: nil,
    )
  }

  private init(
    _ model: DisksModel,
    drive: DisksDriveModel,
    disks: [DriveMounterDisk],
    session: DASession,
    connection: DatabasePool,
    authentication: LAContext,
    shouldClearKeychainPassword: Bool,
    currentItem: DriveMounterItem?,
    remainingItems: [DriveMounterItem]?,
  ) {
    self.model = model
    self.drive = drive
    self.disks = disks
    self.session = session
    self.connection = connection
    self.authentication = authentication
    self.shouldClearKeychainPassword = shouldClearKeychainPassword
    self.currentItem = currentItem
    self.remainingItems = remainingItems
  }

  func run() async throws(DisksModelMountDriveError) {
    let mediaIDs = self.disks.map(\.store.mediaID!)
    let volumeIDs = self.disks.map(\.store.volumeID!)
    let request: DisksRequest

    do {
      request = try await connection.read { db in
        let driveDisks = try DriveDiskRecord
          .including(
            required: DriveDiskRecord.disk
              .forKey(DriveDiskRequestData.CodingKeys.disk)
              .filter { mediaIDs.contains($0.mediaID) }
          )
          .asRequest(of: DriveDiskRequestData.self)
          .fetchAll(db)

        let disks = try DiskRecord
          .filter { volumeIDs.contains($0.uuid) }
          .fetchAll(db)

        let request = DisksRequest(driveDisks: driveDisks, disks: disks)

        return request
      }
    } catch {
      throw DisksModelMountDriveError(reason: .database(error))
    }

    let items = self.disks.map { disk in
      let hasKeychainPassword: Bool
      let keychainPasswordAccount: String?

      if let request = request.driveDisks.first(where: { $0.disk.disk.mediaID! == disk.store.mediaID! }) {
        hasKeychainPassword = request.driveDisk.hasKeychainPassword!
        keychainPasswordAccount = request.driveDisk.id!.uuidString
      } else if let request = request.disks.first(where: { $0.uuid! == disk.store.volumeID! }) {
        hasKeychainPassword = true
        keychainPasswordAccount = request.id!.uuidString
      } else {
        hasKeychainPassword = false
        keychainPasswordAccount = nil
      }

      let item = DriveMounterItem(
        disk: disk,
        hasKeychainPassword: hasKeychainPassword,
        keychainPasswordAccount: keychainPasswordAccount,
      )

      return item
    }

    let needsAuthentication = items.contains { item in
      !item.disk.store.isVolumeMounted!
      && item.disk.store.mediaEncryption.contains(.volume)
      && item.hasKeychainPassword
    }

    if needsAuthentication {
      do {
        try await self.authentication.evaluatePolicy(
          .deviceOwnerAuthentication,
          localizedReason: "unlock the drive “\(self.drive.name)”",
        )
      } catch {
        throw DisksModelMountDriveError(reason: .authentication(error))
      }
    }

    try await self.mount(items: items)
  }

  func resume() async throws(DisksModelMountDriveError) {
    if self.shouldClearKeychainPassword {
      let item = self.currentItem!

      do {
        _ = try await self.connection.write { db in
          try DisksModel.upsertDriveDisk(
            db,
            hasKeychainPassword: false,
            mediaID: item.disk.store.mediaID!,
            volumeID: item.disk.store.volumeID!,
          )
        }
      } catch {
        throw DisksModelMountDriveError(reason: .database(error))
      }
    }
  }

  func resume(password: String) async throws(DisksModelMountDriveError) {
    let item = self.currentItem!

    do {
      try await DisksModel.mount(device: item.disk.disk.device, password: password)
    } catch {
      throw DisksModelMountDriveError(
        reason: .unlock(DisksModelMountDriveUnlockError(device: item.disk.disk.device, underlyingError: error)),
      )
    }

    let id: UUID

    do {
      id = try await self.connection.write { db in
        try DisksModel.upsertDriveDisk(
          db,
          hasKeychainPassword: true,
          mediaID: item.disk.store.mediaID!,
          volumeID: item.disk.store.volumeID!,
        )
      }
    } catch {
      throw DisksModelMountDriveError(reason: .database(error))
    }

    let account = id.uuidString

    do {
      try DisksModel.storeKeychainPassword(
        service: DisksModel.diskPasswordKeychainService,
        account: account,
        password: password,
      )
    } catch {
      throw DisksModelMountDriveError(
        reason: .keychain(DisksModelMountDriveKeychainPasswordError(account: account, underlyingError: error))
      )
    }

    try await self.mount(items: self.remainingItems!)
  }

  private func mount(items: [DriveMounterItem]) async throws(DisksModelMountDriveError) {
    var iterator = items.makeIterator()

    while let item = iterator.next() {
      do {
        try await self.mount(item: item)
      } catch {
        let shouldClearKeychainPassword: Bool

        switch error.reason {
          case .encrypted:
            // A password is required
            shouldClearKeychainPassword = false
          case let .keychain(error):
            switch error.underlyingError.reason {
              case let .database(error) where error.status == errSecItemNotFound:
                // The drive disk ID doesn't exist in the Keychain database.
                shouldClearKeychainPassword = true
              default:
                shouldClearKeychainPassword = false
            }
          case .unlock:
            // The password may be incorrect.
            shouldClearKeychainPassword = false
          default:
            throw error
        }

        let mounter = Self(
          self.model,
          drive: self.drive,
          disks: self.disks,
          session: self.session,
          connection: self.connection,
          authentication: self.authentication,
          shouldClearKeychainPassword: shouldClearKeychainPassword,
          currentItem: item,
          remainingItems: Array(iterator),
        )

        mounter.presentUnlockScene(item: item)

        break
      }
    }
  }

  private func presentUnlockScene(item: DriveMounterItem) {
    self.model.unlockDiskSceneDisk = UnlockDiskModel(mounter: self, disk: item.disk.disk)
    self.model.isUnlockDiskScenePresented = true
  }

  private func mount(item: DriveMounterItem) async throws(DisksModelMountDriveError) {
    if item.disk.store.isVolumeMounted! {
      return
    }

    if item.disk.store.mediaEncryption.contains(.volume) {
      guard item.hasKeychainPassword else {
        throw DisksModelMountDriveError(reason: .encrypted)
      }

      let account = item.keychainPasswordAccount!
      let password: String

      do {
        password = try DisksModel.loadKeychainPassword(
          service: DisksModel.diskPasswordKeychainService,
          account: account,
          authentication: self.authentication,
        )
      } catch let error {
        throw DisksModelMountDriveError(
          reason: .keychain(DisksModelMountDriveKeychainPasswordError(account: account, underlyingError: error))
        )
      }

      do {
        try await DisksModel.mount(device: item.disk.disk.device, password: password)
      } catch {
        throw DisksModelMountDriveError(
          reason: .unlock(DisksModelMountDriveUnlockError(device: item.disk.disk.device, underlyingError: error)),
        )
      }

      return
    }

    guard let disk = DADiskCreateFromBSDName(nil, self.session, item.disk.disk.device) else {
      throw DisksModelMountDriveError(
        reason: .diskArbitration(
          DisksModelMountDriveDiskArbitrationError(device: item.disk.disk.device, reason: .unknownDisk),
        ),
      )
    }

    do {
      try await Disks.mount(disk: disk)
    } catch {
      throw DisksModelMountDriveError(
        reason: .diskArbitration(
          DisksModelMountDriveDiskArbitrationError(device: item.disk.disk.device, reason: .mount(error)),
        ),
      )
    }
  }
}

private struct DriveDiskDiskRequestData {
  let disk: Disk2Record
}

extension DriveDiskDiskRequestData: Decodable, FetchableRecord {}

private struct DriveDiskRequestData {
  let driveDisk: DriveDiskRecord
  let disk: DriveDiskDiskRequestData
}

extension DriveDiskRequestData: Decodable, FetchableRecord {
  enum CodingKeys: String, CodingKey {
    case driveDisk,
         disk = "_disk"
  }
}

private struct DisksRequest {
  let driveDisks: [DriveDiskRequestData]
  let disks: [DiskRecord]
}

struct DisksModelMountDriveKeychainPasswordError {
  let account: String
  let underlyingError: DisksModelKeychainPasswordError
}

struct DisksModelMountDriveUnlockError {
  let device: String
  let underlyingError: DisksModelMountDiskDeviceError
}

enum DisksModelMountDriveDiskArbitrationErrorReason {
  case unknownDisk,
       mount(MountDiskError)
}

struct DisksModelMountDriveDiskArbitrationError {
  let device: String
  let reason: DisksModelMountDriveDiskArbitrationErrorReason
}

extension DisksModelMountDriveDiskArbitrationError: Error {}

enum DisksModelMountDriveErrorReason {
  case database(any Error),
       authentication(any Error),
       encrypted,
       keychain(DisksModelMountDriveKeychainPasswordError),
       unlock(DisksModelMountDriveUnlockError),
       diskArbitration(DisksModelMountDriveDiskArbitrationError)
}

struct DisksModelMountDriveError {
  let reason: DisksModelMountDriveErrorReason
}

extension DisksModelMountDriveError: Error {}

extension DisksModel {
  func mount(drive: DisksDriveModel) async throws(DisksModelMountDriveError) {
    let session = self.session!
    let disks = drive.disks.compactMap { disk -> DriveMounterDisk? in
      guard let store = self.disks[disk.device] else {
        return nil
      }

      let disk = DriveMounterDisk(store: store, disk: disk)

      return disk
    }

    let connection: DatabasePool

    do {
      connection = try await databaseConnection()
    } catch {
      throw DisksModelMountDriveError(reason: .database(error))
    }

    let mounter = DriveMounter(
      self,
      drive: drive,
      disks: disks,
      session: session.session,
      connection: connection,
    )

    try await mounter.run()
  }
}
