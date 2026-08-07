//
//  DisksModel+DiskMount.swift
//  Disks
//
//  Created by Kyle Erhabor on 8/2/26.
//

import Foundation
import GRDB
import LocalAuthentication

private enum DiskMounterDiskRequest {
  case driveDisk(DriveDiskRecord),
       disk(DiskRecord)
}

private struct DiskMounter: DisksModelMounter {
  let model: DisksModel
  let store: DisksModelDisk
  let disk: DisksDriveDiskModel

  // MARK: Disk Arbitration
  let session: DASession

  // MARK: Database
  let connection: DatabasePool

  // MARK: -
  private let shouldClearKeychainPassword: Bool

  init(_ model: DisksModel, store: DisksModelDisk, disk: DisksDriveDiskModel, session: DASession, connection: DatabasePool) {
    self.init(
      model,
      store: store,
      disk: disk,
      session: session,
      connection: connection,
      shouldClearKeychainPassword: false,
    )
  }

  private init(
    _ model: DisksModel,
    store: DisksModelDisk,
    disk: DisksDriveDiskModel,
    session: DASession,
    connection: DatabasePool,
    shouldClearKeychainPassword: Bool,
  ) {
    self.model = model
    self.store = store
    self.disk = disk
    self.session = session
    self.connection = connection
    self.shouldClearKeychainPassword = shouldClearKeychainPassword
  }

  func run() async throws(DisksModelMountDiskError) {
    if self.store.mediaEncryption.contains(.volume) {
      let request: DiskMounterDiskRequest?

      do {
        request = try await self.connection.read { db in
          let driveDisk = DriveDiskRecord.including(
            required: DriveDiskRecord.disk.filter(key: [Disk2Record.Columns.mediaID.name: self.store.mediaID!])
          )

          if let disk = try driveDisk.fetchOne(db) {
            return .driveDisk(disk)
          }

          if let disk = try DiskRecord.fetchOne(db, key: [DiskRecord.Columns.uuid.name: self.store.volumeID!]) {
            return .disk(disk)
          }

          return nil
        }
      } catch {
        throw DisksModelMountDiskError(reason: .database(error))
      }


      let hasKeychainPassword: Bool
      let keychainAccount: String?

      if let request {
        switch request {
          case let .driveDisk(disk):
            hasKeychainPassword = disk.hasKeychainPassword!
            keychainAccount = disk.id!.uuidString
          case let .disk(disk):
            hasKeychainPassword = true
            keychainAccount = disk.id!.uuidString
        }
      } else {
        hasKeychainPassword = false
        keychainAccount = nil
      }

      guard hasKeychainPassword else {
        self.presentUnlockScene()

        return
      }

      let account = keychainAccount!
      let authentication = LAContext()

      do {
        try await authentication.evaluatePolicy(
          .deviceOwnerAuthentication,
          localizedReason: "unlock the drive “\(self.disk.name)”",
        )
      } catch {
        throw DisksModelMountDiskError(reason: .authentication(error))
      }

      let password: String

      do {
        password = try DisksModel.loadKeychainPassword(
          service: DisksModel.diskPasswordKeychainService,
          account: account,
          authentication: authentication,
        )
      } catch let error {
        switch error.reason {
          case let .database(error) where error.status == errSecItemNotFound:
            break
          default:
            throw DisksModelMountDiskError(
              reason: .keychain(DisksModelMountDiskKeychainPasswordError(account: account, underlyingError: error)),
            )
        }

        let mounter = Self(
          self.model,
          store: self.store,
          disk: self.disk,
          session: self.session,
          connection: self.connection,
          shouldClearKeychainPassword: true,
        )

        mounter.presentUnlockScene()

        return
      }

      do {
        try await DisksModel.mount(device: self.disk.device, password: password)
      } catch {
        self.presentUnlockScene()

        throw DisksModelMountDiskError(
          reason: .unlock(DisksModelMountDiskUnlockError(device: self.disk.device, underlyingError: error)),
        )
      }

      return
    }

    guard let disk = DADiskCreateFromBSDName(nil, self.session, self.disk.device) else {
      throw DisksModelMountDiskError(
        reason: .diskArbitration(
          DisksModelMountDiskDiskArbitrationError(device: self.disk.device, reason: .unknownDisk),
        ),
      )
    }

    do {
      try await Disks.mount(disk: disk)
    } catch {
      throw DisksModelMountDiskError(
        reason: .diskArbitration(
          DisksModelMountDiskDiskArbitrationError(device: self.disk.device, reason: .mount(error)),
        ),
      )
    }
  }

  func resume() async throws(DisksModelMountDiskError) {
    if self.shouldClearKeychainPassword {
      do {
        _ = try await self.connection.write { db in
          try DisksModel.upsertDriveDisk(
            db,
            hasKeychainPassword: false,
            mediaID: self.store.mediaID!,
            volumeID: self.store.volumeID!,
          )
        }
      } catch {
        throw DisksModelMountDiskError(reason: .database(error))
      }
    }
  }

  func resume(password: String) async throws(DisksModelMountDiskError) {
    do {
      try await DisksModel.mount(device: self.disk.device, password: password)
    } catch {
      self.presentUnlockFailureScene()

      throw DisksModelMountDiskError(
        reason: .unlock(DisksModelMountDiskUnlockError(device: self.disk.device, underlyingError: error)),
      )
    }

    let id: UUID

    do {
      id = try await self.connection.write { db in
        try DisksModel.upsertDriveDisk(
          db,
          hasKeychainPassword: true,
          mediaID: self.store.mediaID!,
          volumeID: self.store.volumeID!,
        )
      }
    } catch {
      throw DisksModelMountDiskError(reason: .database(error))
    }

    let account = id.uuidString

    do {
      try DisksModel.storeKeychainPassword(
        service: DisksModel.diskPasswordKeychainService,
        account: account,
        password: password,
      )
    } catch {
      throw DisksModelMountDiskError(
        reason: .keychain(DisksModelMountDiskKeychainPasswordError(account: account, underlyingError: error))
      )
    }
  }

  private func presentUnlockScene() {
    self.model.unlockDiskSceneDisk = UnlockDiskModel(mounter: self, disk: self.disk)
    self.model.isUnlockDiskScenePresented = true
  }

  private func presentUnlockFailureScene() {
    self.model.unlockFailureDiskSceneDisk = UnlockFailureDiskModel(disk: self.disk)
    self.model.isUnlockFailureDiskScenePresented = true
  }
}


struct DisksModelMountDiskKeychainPasswordError {
  let account: String
  let underlyingError: DisksModelKeychainPasswordError
}

enum DisksModelMountDiskDiskArbitrationErrorReason {
  case unknownDisk,
       mount(MountDiskError)
}

struct DisksModelMountDiskDiskArbitrationError {
  let device: String
  let reason: DisksModelMountDiskDiskArbitrationErrorReason
}

struct DisksModelMountDiskUnlockError {
  let device: String
  let underlyingError: DisksModelMountDiskDeviceError
}

enum DisksModelMountDiskErrorReason {
  case database(any Error),
       authentication(any Error),
       keychain(DisksModelMountDiskKeychainPasswordError),
       diskArbitration(DisksModelMountDiskDiskArbitrationError),
       unlock(DisksModelMountDiskUnlockError)
}

struct DisksModelMountDiskError {
  let reason: DisksModelMountDiskErrorReason
}

extension DisksModelMountDiskError: Error {}

extension DisksModel {
  func mount(disk: DisksDriveDiskModel) async throws(DisksModelMountDiskError) {
    guard let store = self.disks[disk.device] else {
      return
    }

    let session = self.session!
    let connection: DatabasePool

    do {
      connection = try await databaseConnection()
    } catch {
      throw DisksModelMountDiskError(reason: .database(error))
    }

    let mounter = DiskMounter(self, store: store, disk: disk, session: session.session, connection: connection)
    try await mounter.run()
  }
}
