//
//  DisksModel.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/16/26.
//

import DiskArbitration
import Foundation
import IOKit.kext
import Observation
import OSLog
import SwiftUI

private func device(disk: DADisk) -> String? {
  // This is nil on {id = /System/Volumes/Data/home?owner=0}
  guard let bsdName = DADiskGetBSDName(disk) else {
    return nil
  }

  let name = String(cString: bsdName)

  return name
}

struct DiskSession {
  let session: DASession
  let queue: DispatchQueue

  init(session: DASession, queue: DispatchQueue) {
    self.session = session
    self.queue = queue
  }
}

struct DiskAppearedAction {
  let callback: DADiskAppearedCallback
  let context: UnsafeMutableRawPointer?

  init(context: UnsafeMutableRawPointer? = nil, callback: DADiskAppearedCallback) {
    self.callback = callback
    self.context = context
  }
}

struct DiskDisappearedAction {
  let callback: DADiskDisappearedCallback
  let context: UnsafeMutableRawPointer?

  init(context: UnsafeMutableRawPointer? = nil, callback: DADiskDisappearedCallback) {
    self.callback = callback
    self.context = context
  }
}

struct DiskDescriptionChangedAction {
  let callback: DADiskDescriptionChangedCallback
  let context: UnsafeMutableRawPointer?

  init(context: UnsafeMutableRawPointer? = nil, callback: DADiskDescriptionChangedCallback) {
    self.callback = callback
    self.context = context
  }
}

struct DiskMountApprovalAction {
  let callback: DADiskMountApprovalCallback
  let context: UnsafeMutableRawPointer?

  init(context: UnsafeMutableRawPointer? = nil, callback: DADiskMountApprovalCallback) {
    self.callback = callback
    self.context = context
  }
}

struct DiskUnmountApprovalAction {
  let callback: DADiskUnmountApprovalCallback
  let context: UnsafeMutableRawPointer?

  init(context: UnsafeMutableRawPointer? = nil, callback: DADiskUnmountApprovalCallback) {
    self.callback = callback
    self.context = context
  }
}

@Observable
@MainActor
final class DiskGroupItemModel {
  let uuid: UUID
  let device: String
  var name: String
  var icon: Image
  var isMounted: Bool

  init(uuid: UUID, device: String, name: String, icon: Image, isMounted: Bool) {
    self.uuid = uuid
    self.device = device
    self.name = name
    self.icon = icon
    self.isMounted = isMounted
  }
}

extension DiskGroupItemModel: Identifiable {
  var id: some Hashable {
    self.device
  }
}

@Observable
@MainActor
final class DiskGroupModel {
  let device: String
  var name: String
  var items: [DiskGroupItemModel]

  init(device: String, name: String, items: [DiskGroupItemModel]) {
    self.device = device
    self.name = name
    self.items = items
  }
}

extension DiskGroupModel: Identifiable {
  var id: some Hashable {
    self.device
  }
}

@Observable
@MainActor
final class DiskImageGroupModel {
  let device: String
  var items: [DiskGroupItemModel]

  init(device: String, items: [DiskGroupItemModel]) {
    self.device = device
    self.items = items
  }
}

extension DiskImageGroupModel: Identifiable {
  var id: some Hashable {
    self.device
  }
}

// MARK: - TODO: Rename

@MainActor
struct DiskModel {
  let uuid: UUID
  let device: String
  let name: String
}

@MainActor
struct DiskImageModel {
  let uuid: UUID
  let name: String
  let url: URL
}

private struct DisksModelDisk {
  let isDeviceInternal: Bool?
  let mediaName: String
  let mediaIcon: NSImage
  let volumeID: UUID?
  let volumeName: String?
  let isVolumeMounted: Bool?
}

private enum DisksModelEvent {
  case appeared(String),
       disappeared(String),
       descriptionChanged(String)
}

private struct DisksModelProcessNoDataError: Error {}

private enum DisksModelProcessError: Error {
  case input(any Error),
       output(any Error)
}

struct DisksModelItem {
  let device: String
  let wholeDevice: String
  let isFromDiskImage: Bool
  let mediaName: String
  let mediaIcon: NSImage
  let isDeviceInternal: Bool?
  let volumeID: UUID?
  let volumeName: String?
  let isVolumeMounted: Bool?

  init(
    device: String,
    wholeDevice: String,
    isFromDiskImage: Bool,
    mediaName: String,
    mediaIcon: NSImage,
    isDeviceInternal: Bool?,
    volumeID: UUID?,
    volumeName: String?,
    isVolumeMounted: Bool?,
  ) {
    self.device = device
    self.wholeDevice = wholeDevice
    self.isFromDiskImage = isFromDiskImage
    self.mediaName = mediaName
    self.mediaIcon = mediaIcon
    self.isDeviceInternal = isDeviceInternal
    self.volumeID = volumeID
    self.volumeName = volumeName
    self.isVolumeMounted = isVolumeMounted
  }
}

@Observable
@MainActor
final class DisksModel {
  // MARK: - Disk alert scene
  var diskSceneDisk: DiskModel?
  var isDiskScenePresented = false

  // MARK: - Disk image alert scene
  var diskImageSceneImage: DiskImageModel?
  var isDiskImageScenePresented = false

  // MARK: - Unlock failed alert scene
  var isUnlockFailedScenePresented = false

  // MARK: -
  private(set) var diskGroups = [DiskGroupModel]()
  private(set) var diskImageGroups = [DiskImageGroupModel]()
  private(set) var disks = [String: DisksModelItem]()
  @ObservationIgnored private(set) var session: DiskSession?
  @ObservationIgnored private(set) var appearedAction: DiskAppearedAction?
  @ObservationIgnored private(set) var disappearedAction: DiskDisappearedAction?
  @ObservationIgnored private(set) var descriptionChangedAction: DiskDescriptionChangedAction?
  @ObservationIgnored private(set) var mountApprovalAction: DiskMountApprovalAction?
  @ObservationIgnored private(set) var unmountApprovalAction: DiskUnmountApprovalAction?
  @ObservationIgnored private var sessionContinuation: AsyncStream<DisksModelEvent>.Continuation?
  @ObservationIgnored private var sessionTask: Task<Void, Never>?

  func start() {
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

  @discardableResult
  nonisolated func process(
    executable: URL,
    arguments: [String],
    data: some DataProtocol,
  ) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      let process = Process()
      process.executableURL = executable
      process.arguments = arguments

      let input = Pipe()
      process.standardInput = input

      let output = Pipe()
      process.standardOutput = output
      process.terminationHandler = { process in
        let data: Data?

        do {
          data = try output.fileHandleForReading.readToEnd()
        } catch {
          continuation.resume(throwing: DisksModelProcessError.output(error))

          return
        }

        guard let data else {
          continuation.resume(throwing: DisksModelProcessError.output(DisksModelProcessNoDataError()))

          return
        }

        continuation.resume(returning: data)
      }

      do {
        try process.run()
      } catch {
        continuation.resume(throwing: DisksModelProcessError.input(error))

        return
      }

      do {
        try input.fileHandleForWriting.write(contentsOf: data)
      } catch {
        continuation.resume(throwing: DisksModelProcessError.input(error))

        return
      }

      do {
        try input.fileHandleForWriting.close()
      } catch {
        continuation.resume(throwing: DisksModelProcessError.input(error))

        return
      }
    }
  }

  private func set(item: DisksModelItem, items: [DiskGroupItemModel]) -> DiskGroupItemModel? {
    guard item.isDeviceInternal != true,
          let id = item.volumeID else {
      return nil
    }

    let groupItem: DiskGroupItemModel

    if let model = items.first(where: { $0.device == item.device }) {
      model.name = item.volumeName!
      model.icon = Image(nsImage: item.mediaIcon)
      model.isMounted = item.isVolumeMounted!
      groupItem = model
    } else {
      groupItem = DiskGroupItemModel(
        uuid: id,
        device: item.device,
        name: item.volumeName!,
        icon: Image(nsImage: item.mediaIcon),
        isMounted: item.isVolumeMounted!,
      )
    }

    return groupItem
  }

  private func set() {
    self.diskGroups = Dictionary(grouping: self.disks.values, by: \.wholeDevice)
      .compactMap { (wholeDevice, items) in
        guard let whole = items.first(where: { $0.device == wholeDevice }),
              !whole.isFromDiskImage else {
          return nil
        }

        let group: DiskGroupModel

        if let model = self.diskGroups.first(where: { $0.device == whole.device }) {
          model.name = whole.mediaName
          group = model
        } else {
          group = DiskGroupModel(device: whole.device, name: whole.mediaName, items: [])
        }

        let items = items
          .compactMap { self.set(item: $0, items: group.items) }
          .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        group.items = items

        return group
      }
      .filter { !$0.items.isEmpty }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    self.diskImageGroups = Dictionary(grouping: self.disks.values, by: \.wholeDevice)
      .compactMap { (wholeDevice, items) in
        guard let whole = items.first(where: { $0.device == wholeDevice }),
              whole.isFromDiskImage else {
          return nil
        }

        let group = self.diskImageGroups.first { $0.device == whole.device }
        ?? DiskImageGroupModel(device: whole.device, items: [])

        let items = items
          .compactMap { self.set(item: $0, items: group.items) }
          .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        group.items = items

        return group
      }
      .filter { !$0.items.isEmpty }
  }

  private func addDisk(device: String, wholeDevice: String, isFromDiskImage: Bool, disk: DisksModelDisk) {
    self.disks[device] = DisksModelItem(
      device: device,
      wholeDevice: wholeDevice,
      isFromDiskImage: isFromDiskImage,
      mediaName: disk.mediaName,
      mediaIcon: disk.mediaIcon,
      isDeviceInternal: disk.isDeviceInternal,
      volumeID: disk.volumeID,
      volumeName: disk.volumeName,
      isVolumeMounted: disk.isVolumeMounted,
    )

    self.set()
  }

  private func removeDisk(device: String) {
    guard self.disks.removeValue(forKey: device) != nil else {
      return
    }

    self.set()
  }

  private func updateDisk(device: String, disk: DisksModelDisk) {
    guard let item = self.disks[device] else {
      return
    }

    self.disks[device] = DisksModelItem(
      device: item.device,
      wholeDevice: item.wholeDevice,
      isFromDiskImage: item.isFromDiskImage,
      mediaName: disk.mediaName,
      mediaIcon: disk.mediaIcon,
      isDeviceInternal: item.isDeviceInternal,
      volumeID: item.volumeID,
      volumeName: disk.volumeName,
      isVolumeMounted: disk.isVolumeMounted,
    )

    self.set()
  }

  nonisolated private func handleAppear(device: String, session: DASession) async {
    guard let disk = DADiskCreateFromBSDName(nil, session, device) else {
      return
    }

    let wholeDevice: String

    do {
      wholeDevice = try await self.wholeDevice(name: device)
    } catch let error {
      switch error.code {
        case .notFound:
          break
        default:
          Logger.ui.error("Could not find whole device: \(error)")
      }

      return
    }

    let isFromDiskImage: Bool

    do {
      isFromDiskImage = try await self.isDiskImage(device: wholeDevice)
    } catch {
      Logger.ui.error("\(error)")

      return
    }

    await self.addDisk(
      device: device,
      wholeDevice: wholeDevice,
      isFromDiskImage: isFromDiskImage,
      disk: self.disk(disk: disk),
    )
  }

  private func handleDisappear(device: String) {
    self.removeDisk(device: device)
  }

  nonisolated private func handleDescriptionChange(device: String, session: DASession) async {
    guard let disk = DADiskCreateFromBSDName(nil, session, device) else {
      return
    }

    await self.updateDisk(device: device, disk: self.disk(disk: disk))
  }

  nonisolated private func disk(disk: DADisk) -> DisksModelDisk {
    let description = DADiskCopyDescription(disk) as! [AnyHashable: Any]
    let isDeviceInternal: Bool?

    if let isInternal = description[kDADiskDescriptionDeviceInternalKey] {
      isDeviceInternal = (isInternal as! Bool)
    } else {
      isDeviceInternal = nil
    }

    let name = description[kDADiskDescriptionMediaNameKey] as! String
    let icon = self.icon(description: description)
    let volumeID: UUID?
    let volumeName: String?
    let isVolumeMounted: Bool?

    if let uuid = description[kDADiskDescriptionVolumeUUIDKey],
       let name = description[kDADiskDescriptionVolumeNameKey] {
      // https://developer.apple.com/documentation/foundation/nsuuid
      //
      //   The NSUUID class is not toll-free bridged with CoreFoundation’s CFUUID.
      let uuid = uuid as! CFUUID
      let id = UUID(uuidString: CFUUIDCreateString(nil, uuid) as String)!
      volumeID = id
      volumeName = (name as! String)
      isVolumeMounted = description[kDADiskDescriptionVolumePathKey] != nil
    } else {
      volumeID = nil
      volumeName = nil
      isVolumeMounted = nil
    }

    let disk = DisksModelDisk(
      isDeviceInternal: isDeviceInternal,
      mediaName: name,
      mediaIcon: icon,
      volumeID: volumeID,
      volumeName: volumeName,
      isVolumeMounted: isVolumeMounted,
    )

    return disk
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
}
