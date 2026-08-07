//
//  DisksModel.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/16/26.
//

import DiskArbitration
import Foundation
import GRDB
import IOKit.kext
import IOKit.storage
import LocalAuthentication
import Observation
import OSLog
import SwiftUI
import System

private func device(disk: DADisk) -> String? {
  // This is nil on {id = /System/Volumes/Data/home?owner=0}
  guard let bsdName = DADiskGetBSDName(disk) else {
    return nil
  }

  let name = String(cString: bsdName)

  return name
}

extension UUID {
  static let apfsPartition = Self(uuidString: "41504653-0000-11AA-AA11-00306543ECAC")!
}

struct DiskSession {
  let session: DASession
  let queue: DispatchQueue

  init(session: DASession, queue: DispatchQueue) {
    self.session = session
    self.queue = queue
  }
}

private struct DiskAppearedAction {
  let callback: DADiskAppearedCallback
  let context: UnsafeMutableRawPointer?

  init(context: UnsafeMutableRawPointer? = nil, callback: DADiskAppearedCallback) {
    self.callback = callback
    self.context = context
  }
}

private struct DiskDisappearedAction {
  let callback: DADiskDisappearedCallback
  let context: UnsafeMutableRawPointer?

  init(context: UnsafeMutableRawPointer? = nil, callback: DADiskDisappearedCallback) {
    self.callback = callback
    self.context = context
  }
}

private struct DiskDescriptionChangedAction {
  let callback: DADiskDescriptionChangedCallback
  let context: UnsafeMutableRawPointer?

  init(context: UnsafeMutableRawPointer? = nil, callback: DADiskDescriptionChangedCallback) {
    self.callback = callback
    self.context = context
  }
}

private struct DiskMountApprovalAction {
  let callback: DADiskMountApprovalCallback
  let context: UnsafeMutableRawPointer?

  init(context: UnsafeMutableRawPointer? = nil, callback: DADiskMountApprovalCallback) {
    self.callback = callback
    self.context = context
  }
}

private struct DiskUnmountApprovalAction {
  let callback: DADiskUnmountApprovalCallback
  let context: UnsafeMutableRawPointer?

  init(context: UnsafeMutableRawPointer? = nil, callback: DADiskUnmountApprovalCallback) {
    self.callback = callback
    self.context = context
  }
}

@MainActor
protocol DisksModelMounter {
  associatedtype Failure: Error

  func run() async throws(Failure)

  func resume() async throws(Failure)

  func resume(password: String) async throws(Failure)
}

@Observable
@MainActor
final class DisksDriveDiskModel {
  let device: String
  var name: String
  var icon: Image
  var isMounted: Bool

  init(device: String, name: String, icon: Image, isMounted: Bool) {
    self.device = device
    self.name = name
    self.icon = icon
    self.isMounted = isMounted
  }
}

extension DisksDriveDiskModel: Identifiable {
  var id: some Hashable {
    self.device
  }
}

enum DisksDriveModelSource {
  case disk, diskImage
}

@Observable
@MainActor
final class DisksDriveModel {
  let device: String
  let source: DisksDriveModelSource
  var name: String
  var isMounted: Bool
  var disks: [DisksDriveDiskModel]

  init(device: String, source: DisksDriveModelSource, name: String, isMounted: Bool, disks: [DisksDriveDiskModel]) {
    self.device = device
    self.source = source
    self.name = name
    self.isMounted = isMounted
    self.disks = disks
  }
}

extension DisksDriveModel: Identifiable {
  var id: some Hashable {
    self.device
  }
}

private enum DisksModelEvent {
  case appeared(String),
       disappeared(String),
       descriptionChanged(String)
}

private struct DisksModelItem {
  // MARK: Device
  let deviceSerial: String?
  let isDeviceInternal: Bool?

  // MARK: Media
  let mediaID: UUID?
  let mediaContent: String
  let mediaName: String
  let mediaIcon: NSImage
  let mediaEncryption: DisksModelDiskMediaEncryption

  // MARK: Volume
  let volumeID: UUID?
  let volumeName: String?
  let isVolumeMounted: Bool?
}

struct DisksModelDiskDiskSource {
  let serial: String
}

struct DisksModelDiskDiskImageSource {
  let name: String
}

enum DisksModelDiskSource {
  case disk(DisksModelDiskDiskSource),
       diskImage(DisksModelDiskDiskImageSource)
}

// This took a bit to reverse engineer.
struct DisksModelDiskMediaEncryption {
  let rawValue: UInt

  // e.g., Encrypted disk image
  static let media = Self(rawValue: 1 << 0)

  // e.g., FileVault
  static let volume = Self(rawValue: 1 << 1)
}

extension DisksModelDiskMediaEncryption: OptionSet {}

struct DisksModelDisk {
  let device: String
  let rootDevice: String
  let source: DisksModelDiskSource

  // MARK: Device
  let isDeviceInternal: Bool?

  // MARK: Media
  let mediaID: UUID?
  let mediaContent: String
  let mediaName: String
  let mediaIcon: NSImage
  let mediaEncryption: DisksModelDiskMediaEncryption

  // MARK: Volume
  let volumeID: UUID?
  let volumeName: String?
  let isVolumeMounted: Bool?
}

struct UnlockFailureDiskImage {
  let name: String
}

@Observable
@MainActor
final class DisksModel {
  // MARK: Unlock disk scene
  var unlockDiskSceneDisk: UnlockDiskModel?
  var isUnlockDiskScenePresented = false

  // MARK: Unlock failure disk scene
  var unlockFailureDiskSceneDisk: UnlockFailureDiskModel?
  var isUnlockFailureDiskScenePresented = false

  // MARK: Unmount disk busy scene
  var unmountBusyDiskSceneBusyDisk: UnmountBusyDiskModel?
  var isUnmountBusyDiskScenePresented = false

  // MARK: Rename disk drive scene
  var renameDiskDriveSceneDrive: RenameDriveModel?
  var isRenameDiskDriveScenePresented = false

  // MARK: Unlock disk image scene
  var unlockDiskImageSceneDiskImage: UnlockDiskImageModel?
  var isUnlockDiskImageScenePresented = false

  // MARK: Unlock failure disk image scene
  var unlockFailureDiskImageSceneDiskImage: UnlockFailureDiskImage?
  var isUnlockFailureDiskImageScenePresented = false

  // MARK: -
  private(set) var diskDrives = [DisksDriveModel]()
  private(set) var diskImageDrives = [DisksDriveModel]()

  // MARK: Database
  @ObservationIgnored private var driveNames = [String: String]()
  @ObservationIgnored private var driveNamesTask: Task<Void, Never>?

  // MARK: Disk Arbitration
  @ObservationIgnored private(set) var disks = [String: DisksModelDisk]()
  @ObservationIgnored private(set) var session: DiskSession?
  @ObservationIgnored private var appearedAction: DiskAppearedAction?
  @ObservationIgnored private var disappearedAction: DiskDisappearedAction?
  @ObservationIgnored private var descriptionChangedAction: DiskDescriptionChangedAction?
  @ObservationIgnored private var mountApprovalAction: DiskMountApprovalAction?
  @ObservationIgnored private var unmountApprovalAction: DiskUnmountApprovalAction?
  @ObservationIgnored private var sessionContinuation: AsyncStream<DisksModelEvent>.Continuation?
  @ObservationIgnored private var sessionTask: Task<Void, Never>?

  func start() {
    self.driveNamesTask = Task { [weak self] in
      guard let self else {
        return
      }

      let connection: DatabasePool

      do {
        connection = try await databaseConnection()
      } catch {
        Logger.model.error("\(error)")

        return
      }

      let observation = ValueObservation.trackingConstantRegion { db in
        try DiskDriveRecord
          .filter(DiskDriveRecord.Columns.name != nil)
          .fetchAll(db)
      }

      do {
        for try await drives in observation.values(in: connection) {
          self.driveNames = drives.reduce(into: [:]) { partialResult, drive in
            partialResult[drive.serial!] = drive.name!
          }

          self.set()
        }
      } catch {
        Logger.model.error("\(error)")

        return
      }
    }

    guard let s = DASessionCreate(nil) else {
      fatalError()
    }

    let queue = DispatchQueue(label: "\(Bundle.appID).disk-arbitration", target: .global(qos: .default))
    let session = DiskSession(session: s, queue: queue)
    let stream = AsyncStream<DisksModelEvent>.makeStream()
    self.sessionContinuation = stream.continuation
    self.sessionTask = Task { [weak self] in
      guard let self else {
        return
      }

      for await event in stream.stream {
        switch event {
          case let .appeared(device):
            await self.handleAppear(device: device, session: session.session)
          case let .disappeared(device):
            self.handleDisappear(device: device)
          case let .descriptionChanged(device):
            await self.handleDescriptionChange(device: device, session: session.session)
        }
      }
    }

    let context = Unmanaged.passUnretained(self).toOpaque()

    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0302-concurrent-value-and-concurrent-closures.md
    //
    //   C function pointers conform to the Sendable protocol. This is safe because they cannot capture values.

    let appeared = DiskAppearedAction(context: context) { disk, context in
      let context = Unmanaged<DisksModel>.fromOpaque(context!).takeUnretainedValue()

      guard let device = device(disk: disk) else {
        return
      }

      context.sessionContinuation!.yield(.appeared(device))
    }

    DARegisterDiskAppearedCallback(session.session, nil, appeared.callback, appeared.context)

    let disappeared = DiskDisappearedAction(context: context) { disk, context in
      let context = Unmanaged<DisksModel>.fromOpaque(context!).takeUnretainedValue()

      guard let device = device(disk: disk) else {
        return
      }

      context.sessionContinuation!.yield(.disappeared(device))
    }

    DARegisterDiskDisappearedCallback(session.session, nil, disappeared.callback, disappeared.context)

    let descriptionChanged = DiskDescriptionChangedAction(context: context) { disk, keys, context in
      let context = Unmanaged<DisksModel>.fromOpaque(context!).takeUnretainedValue()

      guard let device = device(disk: disk) else {
        return
      }

      context.sessionContinuation!.yield(.descriptionChanged(device))
    }

    DARegisterDiskDescriptionChangedCallback(
      session.session,
      nil,
      nil,
      descriptionChanged.callback,
      descriptionChanged.context,
    )

    let mountApproval = DiskMountApprovalAction(context: context) { _, _ in nil }
    DARegisterDiskMountApprovalCallback(session.session, nil, mountApproval.callback, mountApproval.context)

    let unmountApproval = DiskUnmountApprovalAction(context: context) { _, _ in nil }
    DARegisterDiskUnmountApprovalCallback(session.session, nil, unmountApproval.callback, unmountApproval.context)

    // Start session
    DASessionSetDispatchQueue(session.session, session.queue)

    self.session = session
    self.appearedAction = appeared
    self.disappearedAction = disappeared
    self.descriptionChangedAction = descriptionChanged
    self.mountApprovalAction = mountApproval
    self.unmountApprovalAction = unmountApproval
  }

  func stop() {
    self.driveNamesTask!.cancel()
    self.driveNamesTask = nil

    let session = self.session!
    // Stop session
    DASessionSetDispatchQueue(session.session, nil)

    let unmountApproval = self.unmountApprovalAction!
    DAUnregisterCallback(
      session.session,
      unsafeBitCast(unmountApproval.callback, to: UnsafeMutableRawPointer.self),
      unmountApproval.context,
    )

    let mountApproval = self.mountApprovalAction!
    DAUnregisterCallback(
      session.session,
      unsafeBitCast(mountApproval.callback, to: UnsafeMutableRawPointer.self),
      mountApproval.context,
    )

    let descriptionChanged = self.descriptionChangedAction!
    DAUnregisterCallback(
      session.session,
      unsafeBitCast(descriptionChanged.callback, to: UnsafeMutableRawPointer.self),
      descriptionChanged.context,
    )

    let disappeared = self.disappearedAction!
    DAUnregisterCallback(
      session.session,
      unsafeBitCast(disappeared.callback, to: UnsafeMutableRawPointer.self),
      disappeared.context,
    )

    let appeared = self.appearedAction!
    DAUnregisterCallback(
      session.session,
      unsafeBitCast(appeared.callback, to: UnsafeMutableRawPointer.self),
      appeared.context,
    )

    self.sessionContinuation!.finish()
    self.sessionTask!.cancel()

    self.session = nil
    self.sessionContinuation = nil
    self.sessionTask = nil
    self.appearedAction = nil
    self.disappearedAction = nil
    self.descriptionChangedAction = nil
    self.mountApprovalAction = nil
    self.unmountApprovalAction = nil
  }

  func presentRenameDriveScene(drive: DisksDriveModel) {
    let disk = self.disks[drive.device]!

    switch disk.source {
      case let .disk(source):
        let serial = source.serial
        self.renameDiskDriveSceneDrive = RenameDriveModel(
          continuation: DisksDriveRenameDriveContinuation(
            source: .disk(DisksDriveRenameDriveContinuationDiskDriveSource(serial: serial))
          ),
          originalName: disk.mediaName,
          name: self.driveNames[serial] ?? "",
        )

        self.isRenameDiskDriveScenePresented = true
      case .diskImage:
        unreachable()
    }
  }

  private func set(item: DisksModelDisk, disks: [DisksDriveDiskModel]) -> DisksDriveDiskModel? {
    guard item.isDeviceInternal != true,
          let content = UUID(uuidString: item.mediaContent),
          content == .apfsPartition else {
      return nil
    }

    let groupItem: DisksDriveDiskModel

    if let model = disks.first(where: { $0.device == item.device }) {
      model.name = item.volumeName!
      model.icon = Image(nsImage: item.mediaIcon)
      model.isMounted = item.isVolumeMounted!
      groupItem = model
    } else {
      groupItem = DisksDriveDiskModel(
        device: item.device,
        name: item.volumeName!,
        icon: Image(nsImage: item.mediaIcon),
        isMounted: item.isVolumeMounted!,
      )
    }

    return groupItem
  }

  private func set() {
    self.diskDrives = Dictionary(grouping: self.disks.values, by: \.rootDevice)
      .compactMap { (rootDevice, disks) in
        guard // The root disk may not be stored in disks yet.
              let rootDisk = disks.first(where: { $0.device == rootDevice }),
              case let .disk(disk) = rootDisk.source else {
          return nil
        }

        let name = self.driveNames[disk.serial] ?? rootDisk.mediaName
        let drive = self.diskDrives.first(where: { $0.device == rootDisk.device })
        ?? DisksDriveModel(device: rootDisk.device, source: .disk, name: name, isMounted: false, disks: [])

        let items = disks
          .compactMap { self.set(item: $0, disks: drive.disks) }
          .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        drive.name = name
        drive.disks = items
        drive.isMounted = !drive.disks.isEmpty && drive.disks.allSatisfy(\.isMounted)

        return drive
      }
      .filter { !$0.disks.isEmpty }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    self.diskImageDrives = Dictionary(grouping: self.disks.values, by: \.rootDevice)
      .compactMap { (rootDevice, disks) in
        guard let rootDisk = disks.first(where: { $0.device == rootDevice }),
              case let .diskImage(diskImage) = rootDisk.source else {
          return nil
        }

        let name = diskImage.name
        let drive = self.diskDrives.first(where: { $0.device == rootDisk.device })
        ?? DisksDriveModel(device: rootDisk.device, source: .diskImage, name: name, isMounted: false, disks: [])

        let items = disks
          .compactMap { self.set(item: $0, disks: drive.disks) }
          .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        drive.name = name
        drive.disks = items
        drive.isMounted = !drive.disks.isEmpty && drive.disks.allSatisfy(\.isMounted)

        return drive
      }
      .filter { !$0.disks.isEmpty }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  // MARK: Database

  nonisolated static func upsertDriveDisk(
    _ db: Database,
    hasKeychainPassword: Bool,
    mediaID: UUID,
    volumeID: UUID,
  ) throws -> UUID {
    let diskRequest = DriveDiskRecord.including(
      required: DriveDiskRecord.disk.filter(key: [Disk2Record.Columns.mediaID.name: mediaID]),
    )

    if let disk = try diskRequest.fetchOne(db) {
      let driveDisk = DriveDiskRecord(
        rowID: disk.rowID,
        id: nil,
        disk: nil,
        hasKeychainPassword: hasKeychainPassword,
      )

      try driveDisk.update(db, columns: [DriveDiskRecord.Columns.hasKeychainPassword])

      return disk.id!
    }

    if let disk = try DiskRecord.fetchOne(db, key: [DiskRecord.Columns.uuid.name: volumeID]) {
      let id = disk.id!
      let disk = try self.createDisk(db, mediaID: mediaID)
      try self.createDriveDisk(db, id: id, disk: disk, hasKeychainPassword: hasKeychainPassword)
      try disk.delete(db)

      return id
    }

    let id = UUID()
    let disk = try self.createDisk(db, mediaID: mediaID)
    try self.createDriveDisk(db, id: id, disk: disk, hasKeychainPassword: hasKeychainPassword)

    return id
  }

  @discardableResult
  nonisolated static func createDriveDisk(
    _ db: Database,
    id: UUID,
    disk: Disk2Record,
    hasKeychainPassword: Bool,
  ) throws -> DriveDiskRecord {
    var driveDisk = DriveDiskRecord(id: id, disk: disk.rowID, hasKeychainPassword: hasKeychainPassword)
    try driveDisk.insert(db)

    return driveDisk
  }

  @discardableResult
  nonisolated static func createDisk(_ db: Database, mediaID: UUID) throws -> Disk2Record {
    var disk = Disk2Record(mediaID: mediaID)
    try disk.insert(db)

    return disk
  }

  nonisolated static func upsertDiskImageDrive(
    _ db: Database,
    hasKeychainPassword: Bool,
    diskImageID: UUID,
  ) throws -> UUID {
    let diskImageDriveRequest = DiskImageDriveRecord.including(
      required: DiskImageDriveRecord.image.filter(key: [DiskImage2Record.Columns.id.name: diskImageID]),
    )

    if let diskImageDrive = try diskImageDriveRequest.fetchOne(db) {
      let drive = DiskImageDriveRecord(
        rowID: diskImageDrive.rowID,
        id: nil,
        image: nil,
        hasKeychainPassword: hasKeychainPassword,
      )

      try drive.update(db, columns: [DiskImageDriveRecord.Columns.hasKeychainPassword])

      return diskImageDrive.id!
    }

    if let diskImage1 = try DiskImageRecord.fetchOne(db, key: [DiskImageRecord.Columns.uuid.name: diskImageID]) {
      let id = diskImage1.id!
      let diskImage = try self.createDiskImage(db, id: diskImageID)
      try self.createDiskImageDrive(db, id: id, image: diskImage, hasKeychainPassword: hasKeychainPassword)
      try diskImage1.delete(db)

      return id
    }

    let id = UUID()
    let diskImage = try self.createDiskImage(db, id: diskImageID)
    try self.createDiskImageDrive(db, id: id, image: diskImage, hasKeychainPassword: hasKeychainPassword)

    return id
  }

  @discardableResult
  nonisolated static func createDiskImageDrive(
    _ db: Database,
    id: UUID,
    image: DiskImage2Record,
    hasKeychainPassword: Bool,
  ) throws -> DiskImageDriveRecord {
    var diskImageDrive = DiskImageDriveRecord(id: id, image: image.rowID, hasKeychainPassword: hasKeychainPassword)
    try diskImageDrive.insert(db)

    return diskImageDrive
  }

  @discardableResult
  nonisolated static func createDiskImage(_ db: Database, id: UUID) throws -> DiskImage2Record {
    var diskImage = DiskImage2Record(id: id)
    try diskImage.insert(db)

    return diskImage
  }

  // MARK: Disk Arbitration

  private func addDisk(
    device: String,
    rootDevice: String,
    source: DisksModelDiskSource,
    item: DisksModelItem,
  ) {
    self.disks[device] = DisksModelDisk(
      device: device,
      rootDevice: rootDevice,
      source: source,
      isDeviceInternal: item.isDeviceInternal,
      mediaID: item.mediaID,
      mediaContent: item.mediaContent,
      mediaName: item.mediaName,
      mediaIcon: item.mediaIcon,
      mediaEncryption: item.mediaEncryption,
      volumeID: item.volumeID,
      volumeName: item.volumeName,
      isVolumeMounted: item.isVolumeMounted,
    )

    self.set()
  }

  private func removeDisk(device: String) {
    guard self.disks.removeValue(forKey: device) != nil else {
      return
    }

    self.set()
  }

  private func updateDisk(device: String, disk: DisksModelItem) {
    guard let item = self.disks[device] else {
      return
    }

    self.disks[device] = DisksModelDisk(
      device: item.device,
      rootDevice: item.rootDevice,
      source: item.source,
      isDeviceInternal: disk.isDeviceInternal,
      mediaID: disk.mediaID,
      mediaContent: disk.mediaContent,
      mediaName: disk.mediaName,
      mediaIcon: disk.mediaIcon,
      mediaEncryption: disk.mediaEncryption,
      volumeID: disk.volumeID,
      volumeName: disk.volumeName,
      isVolumeMounted: disk.isVolumeMounted,
    )

    self.set()
  }

  nonisolated private func handleAppear(device: String, session: DASession) async {
    guard let disk = DADiskCreateFromBSDName(nil, session, device) else {
      return
    }

    let rootDevice: String

    do {
      rootDevice = try await self.rootDevice(of: device)
    } catch let error {
      Logger.ui.error("\(error)")

      return
    }

    let item = self.item(disk: disk)
    let source: DisksModelDiskSource

    do {
      let path = try await self.diskImagePath(rootDevice: rootDevice)
      source = .diskImage(DisksModelDiskDiskImageSource(name: path.stem!))
    } catch let error {
      guard case .notFound = error.reason else {
        Logger.model.error("\(error)")

        return
      }

      source = .disk(DisksModelDiskDiskSource(serial: item.deviceSerial!))
    }

    await self.addDisk(device: device, rootDevice: rootDevice, source: source, item: item)
  }

  private func handleDisappear(device: String) {
    self.removeDisk(device: device)
  }

  nonisolated private func handleDescriptionChange(device: String, session: DASession) async {
    guard let disk = DADiskCreateFromBSDName(nil, session, device) else {
      return
    }

    await self.updateDisk(device: device, disk: self.item(disk: disk))
  }

  nonisolated private func item(disk: DADisk) -> DisksModelItem {
    let description = DADiskCopyDescription(disk) as! [AnyHashable: Any]
    let isDeviceInternal: Bool?

    if let isInternal = description[kDADiskDescriptionDeviceInternalKey] {
      isDeviceInternal = (isInternal as! Bool)
    } else {
      isDeviceInternal = nil
    }

    let name = description[kDADiskDescriptionMediaNameKey] as! String
    let mediaID: UUID?

    if let id = description[kDADiskDescriptionMediaUUIDKey] {
      mediaID = UUID(id as! CFUUID)
    } else {
      mediaID = nil
    }

    let mediaContent = description[kDADiskDescriptionMediaContentKey] as! String
    let icon = self.icon(description: description)
    let mediaEncryption = DisksModelDiskMediaEncryption(
      rawValue: description[kDADiskDescriptionMediaEncryptionDetailKey] as! UInt,
    )

    let volumeID: UUID?
    let volumeName: String?
    let isVolumeMounted: Bool?

    if let uuid = description[kDADiskDescriptionVolumeUUIDKey],
       let name = description[kDADiskDescriptionVolumeNameKey] {
      volumeID = UUID(uuid as! CFUUID)
      volumeName = (name as! String)
      isVolumeMounted = description[kDADiskDescriptionVolumePathKey] != nil
    } else {
      volumeID = nil
      volumeName = nil
      isVolumeMounted = nil
    }

    let serial = self.serial(from: DADiskCopyIOMedia(disk))
    let item = DisksModelItem(
      deviceSerial: serial,
      isDeviceInternal: isDeviceInternal,
      mediaID: mediaID,
      mediaContent: mediaContent,
      mediaName: name,
      mediaIcon: icon,
      mediaEncryption: mediaEncryption,
      volumeID: volumeID,
      volumeName: volumeName,
      isVolumeMounted: isVolumeMounted,
    )

    return item
  }

  nonisolated private func icon(description: [AnyHashable: Any]) -> NSImage {
    if let url = description[kDADiskDescriptionVolumePathKey] as? URL {
      return NSWorkspace.shared.icon(forFileAt: url)
    }

    // https://github.com/kainjow/Semulov/blob/2bca059cd43b8d42161511ef03a283c495f71dc1/SLDiskManager.m#L123-L132
    let mediaIcon = description[kDADiskDescriptionMediaIconKey] as! [AnyHashable: Any]
    let bundleID = mediaIcon[kCFBundleIdentifierKey] as! CFString
    let bundleResourceFile = mediaIcon[kIOBundleResourceFileKey] as! String
    let url = KextManagerCreateURLForBundleIdentifier(nil, bundleID).takeRetainedValue() as URL
    let bundle = Bundle(url: url)!
    let image = bundle.image(forResource: bundleResourceFile)!

    return image
  }

  nonisolated private func serial(from service: io_service_t) -> String? {
    guard let representation = IORegistryEntrySearchCFProperty(
      service,
      kIOServicePlane,
      "Serial Number" as CFString,
      nil,
      IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents),
    ) else {
      return nil
    }

    let serial = representation as! String

    return serial
  }
}
