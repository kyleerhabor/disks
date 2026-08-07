//
//  DisksModel+DiskImageAttach.swift
//  Disks
//
//  Created by Kyle Erhabor on 8/3/26.
//

import Foundation
import GRDB
import LocalAuthentication
import System

private enum DiskImageMounterDiskImageRequest {
  case diskImageDrive(DiskImageDriveRecord),
       diskImage(DiskImageRecord)
}

private struct DiskImageMounter: DisksModelMounter {
  private let model: DisksModel
  private let url: URL

  // MARK: Database
  private let connection: DatabasePool

  // MARK: -
  private let name: String?
  private let encryption: EncryptionProcessOutput?
  private let shouldClearKeychainPassword: Bool

  init(_ model: DisksModel, url: URL, connection: DatabasePool) {
    self.init(model, url: url, connection: connection, name: nil, encryption: nil, shouldClearKeychainPassword: false)
  }

  private init(
    _ model: DisksModel,
    url: URL,
    connection: DatabasePool,
    name: String?,
    encryption: EncryptionProcessOutput?,
    shouldClearKeychainPassword: Bool,
  ) {
    self.model = model
    self.url = url
    self.connection = connection
    self.name = name
    self.encryption = encryption
    self.shouldClearKeychainPassword = shouldClearKeychainPassword
  }

  func run() async throws(DisksModelAttachDiskImageError) {
    let resourceValues: URLResourceValues

    do {
      resourceValues = try self.url.resourceValues(forKeys: [.localizedNameKey])
    } catch {
      throw DisksModelAttachDiskImageError(reason: .url(DisksModelAttachDiskImageURLError(reason: .resources(error))))
    }

    guard let name = resourceValues.localizedName else {
      throw DisksModelAttachDiskImageError(reason: .url(DisksModelAttachDiskImageURLError(reason: .noLocalizedName)))
    }

    let info: InfoProcessOutput

    do {
      info = try self.decode(output: try await self.process(arguments: ["info", "-plist"]))
    } catch {
      throw DisksModelAttachDiskImageError(reason: .info(error))
    }

    let diskImagePath = FilePath(self.url)!

    if info.images.contains(where: { $0.imagePath == diskImagePath }) {
      // Already attached
      return
    }

    let encryption: EncryptionProcessOutput

    do {
      encryption = try self.decode(output: try await self.process(arguments: ["isencrypted", url.absoluteString, "-plist"]))
    } catch {
      throw DisksModelAttachDiskImageError(reason: .encryption(error))
    }

    if encryption.encrypted {
      let request: DiskImageMounterDiskImageRequest?

      do {
        request = try await connection.read { db in
          let id = encryption.uuid!
          let diskImageDriveRequest = DiskImageDriveRecord.including(
            required: DiskImageDriveRecord.image.filter(key: [DiskImage2Record.Columns.id.name: id]),
          )

          if let drive = try diskImageDriveRequest.fetchOne(db) {
            return .diskImageDrive(drive)
          }

          if let image = try DiskImageRecord.fetchOne(db, key: [DiskImageRecord.Columns.uuid.name: id]) {
            return .diskImage(image)
          }

          return nil
        }
      } catch {
        throw DisksModelAttachDiskImageError(reason: .database(error))
      }

      let hasKeychainPassword: Bool
      let keychainAccount: String?

      if let request {
        switch request {
          case let .diskImageDrive(drive):
            hasKeychainPassword = drive.hasKeychainPassword!
            keychainAccount = drive.id!.uuidString
          case let .diskImage(image):
            hasKeychainPassword = true
            keychainAccount = image.id!.uuidString
        }
      } else {
        hasKeychainPassword = false
        keychainAccount = nil
      }

      guard hasKeychainPassword else {
        let mounter = Self(
          self.model,
          url: self.url,
          connection: self.connection,
          name: name,
          encryption: encryption,
          shouldClearKeychainPassword: false,
        )

        mounter.presentUnlockScene(name: name)

        return
      }

      let context = LAContext()

      do {
        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "unlock the disk image “\(name)”")
      } catch {
        throw DisksModelAttachDiskImageError(reason: .authentication(error))
      }

      let account = keychainAccount!
      let password: String

      do {
        password = try DisksModel.loadKeychainPassword(
          service: DisksModel.diskImagePasswordKeychainService,
          account: account,
          authentication: context,
        )
      } catch {
        switch error.reason {
          case let .database(error) where error.status == errSecItemNotFound:
            break
          default:
            throw DisksModelAttachDiskImageError(
              reason: .keychain(DisksModelAttachDiskImageKeychainPasswordError(account: account, underlyingError: error)),
            )
        }

        let mounter = Self(
          self.model,
          url: self.url,
          connection: self.connection,
          name: name,
          encryption: encryption,
          shouldClearKeychainPassword: true,
        )

        mounter.presentUnlockScene(name: name)

        return
      }

      do {
        try await self.process(
          arguments: ["attach", self.url.absoluteString, "-stdinpass"],
          input: password.data(using: .utf8)!,
        )
      } catch {
        let mounter = Self(
          self.model,
          url: self.url,
          connection: self.connection,
          name: name,
          encryption: encryption,
          shouldClearKeychainPassword: false,
        )

        mounter.presentUnlockScene(name: name)

        throw DisksModelAttachDiskImageError(reason: .attach(error))
      }

      return
    }

    do {
      try await self.process(arguments: ["attach", self.url.absoluteString])
    } catch {
      self.presentUnlockFailureScene(name: name)

      throw DisksModelAttachDiskImageError(reason: .attach(error))
    }
  }

  func resume() async throws(DisksModelAttachDiskImageError) {
    if self.shouldClearKeychainPassword {
      do {
        _ = try await self.connection.write { db in
          try DisksModel.upsertDiskImageDrive(db, hasKeychainPassword: false, diskImageID: self.encryption!.uuid!)
        }
      } catch {
        throw DisksModelAttachDiskImageError(reason: .database(error))
      }
    }
  }

  func resume(password: String) async throws(DisksModelAttachDiskImageError) {
    do {
      try await self.process(
        arguments: ["attach", self.url.absoluteString, "-stdinpass"],
        input: password.data(using: .utf8)!,
      )
    } catch {
      self.presentUnlockFailureScene(name: self.name!)

      throw DisksModelAttachDiskImageError(reason: .attach(error))
    }

    let id: UUID

    do {
      id = try await self.connection.write { db in
        try DisksModel.upsertDiskImageDrive(db, hasKeychainPassword: true, diskImageID: self.encryption!.uuid!)
      }
    } catch {
      throw DisksModelAttachDiskImageError(reason: .database(error))
    }

    let account = id.uuidString

    do {
      try DisksModel.storeKeychainPassword(
        service: DisksModel.diskImagePasswordKeychainService,
        account: account,
        password: password,
      )
    } catch {
      throw DisksModelAttachDiskImageError(
        reason: .keychain(DisksModelAttachDiskImageKeychainPasswordError(account: account, underlyingError: error)),
      )
    }
  }

  private func presentUnlockScene(name: String) {
    self.model.unlockDiskImageSceneDiskImage = UnlockDiskImageModel(mounter: self, url: self.url, name: name)
    self.model.isUnlockDiskImageScenePresented = true
  }

  private func presentUnlockFailureScene(name: String) {
    self.model.unlockFailureDiskImageSceneDiskImage = UnlockFailureDiskImage(name: name)
    self.model.isUnlockFailureDiskImageScenePresented = true
  }

  @discardableResult
  private func process(
    arguments: [String],
    input: some DataProtocol = Data(),
  ) async throws(DisksModelAttachDiskImageProcessError) -> ProcessOutput {
    let output: ProcessOutput

    do {
      output = try await Process.run(executable: .hdiutil, arguments: arguments, input: input)
    } catch {
      throw DisksModelAttachDiskImageProcessError(reason: .run(error))
    }

    guard output.exitStatus == 0 else {
      throw DisksModelAttachDiskImageProcessError(
        reason: .badExit(DisksModelAttachDiskImageProcessBadExitError(status: output.exitStatus)),
      )
    }

    return output
  }

  private func decode<T>(
    output: ProcessOutput,
    as type: T.Type = T.self,
  ) throws(DisksModelAttachDiskImageProcessError) -> T where T: Decodable {
    let decoder = PropertyListDecoder()
    let decoded: T

    do {
      decoded = try decoder.decode(T.self, from: output.output!)
    } catch {
      throw DisksModelAttachDiskImageProcessError(reason: .badOutput)
    }

    return decoded
  }
}

private struct InfoImageProcessOutput {
  let imagePath: FilePath
}

extension InfoImageProcessOutput: Decodable {
  enum CodingKeys: String, CodingKey {
    case imagePath = "image-path"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let imagePath = try container.decode(String.self, forKey: .imagePath)
    self.imagePath = FilePath(imagePath)
  }
}

private struct InfoProcessOutput {
  let images: [InfoImageProcessOutput]
}

extension InfoProcessOutput: Decodable {}

private struct EncryptionProcessOutput {
  let encrypted: Bool
  let uuid: UUID?
}

extension EncryptionProcessOutput: Decodable {}

enum DisksModelAttachDiskImageURLErrorReason {
  case resources(any Error),
       noLocalizedName
}

struct DisksModelAttachDiskImageURLError {
  let reason: DisksModelAttachDiskImageURLErrorReason
}

struct DisksModelAttachDiskImageProcessBadExitError {
  let status: Int32
}

enum DisksModelAttachDiskImageProcessErrorReason {
  case run(ProcessError),
       badExit(DisksModelAttachDiskImageProcessBadExitError),
       badOutput
}

struct DisksModelAttachDiskImageProcessError {
  let reason: DisksModelAttachDiskImageProcessErrorReason
}

extension DisksModelAttachDiskImageProcessError: Error {}

struct DisksModelAttachDiskImageKeychainPasswordError {
  let account: String
  let underlyingError: DisksModelKeychainPasswordError
}

enum DisksModelAttachDiskImageErrorReason {
  case url(DisksModelAttachDiskImageURLError),
       info(DisksModelAttachDiskImageProcessError),
       encryption(DisksModelAttachDiskImageProcessError),
       database(any Error),
       authentication(any Error),
       keychain(DisksModelAttachDiskImageKeychainPasswordError),
       attach(DisksModelAttachDiskImageProcessError)
}

struct DisksModelAttachDiskImageError {
  let reason: DisksModelAttachDiskImageErrorReason
}

extension DisksModelAttachDiskImageError: Error {}

extension DisksModel {
  func attach(diskImageAt url: URL) async throws(DisksModelAttachDiskImageError) {
    let connection: DatabasePool

    do {
      connection = try await databaseConnection()
    } catch {
      throw DisksModelAttachDiskImageError(reason: .database(error))
    }

    let mounter = DiskImageMounter(self, url: url, connection: connection)
    try await mounter.run()
  }
}
