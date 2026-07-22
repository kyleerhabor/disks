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

extension UUID {
  static let efiPartition = Self(uuidString: "C12A7328-F81F-11D2-BA4B-00A0C93EC93B")!
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
final class DiskModel {
  @ObservationIgnored let uuid: UUID
  @ObservationIgnored fileprivate(set) var device: String
  @ObservationIgnored fileprivate(set) var wholeDevice: String
  @ObservationIgnored fileprivate(set) var isFromDiskImage: Bool
  fileprivate(set) var name: String
  fileprivate(set) var icon: Image
  fileprivate(set) var isMounted: Bool

  init(
    uuid: UUID,
    device: String,
    wholeDevice: String,
    isFromDiskImage: Bool,
    name: String,
    icon: Image,
    isMounted: Bool,
  ) {
    self.uuid = uuid
    self.device = device
    self.wholeDevice = wholeDevice
    self.isFromDiskImage = isFromDiskImage
    self.name = name
    self.icon = icon
    self.isMounted = isMounted
  }
}

extension DiskModel: Identifiable {}

private struct DisksModelDisk {
  let id: UUID
  let name: String
  let icon: Image
  let isMounted: Bool
}

@Observable
@MainActor
class DiskImageModel {
  @ObservationIgnored let uuid: UUID
  let name: String
  let url: URL

  init(uuid: UUID, name: String, url: URL) {
    self.uuid = uuid
    self.name = name
    self.url = url
  }
}

private enum DisksModelEvent {
  case appeared(String)
  case disappeared(String)
  case descriptionChanged(String)
}

private struct DisksModelProcessNoDataError: Error {}

private enum DisksModelProcessError: Error {
  case input(any Error),
       output(any Error)
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
  private(set) var disks = [DiskModel]()
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

  private func addDisk(device: String, wholeDevice: String, isFromDiskImage: Bool, disk: DisksModelDisk) {
    self.disks.append(
      DiskModel(
        uuid: disk.id,
        device: device,
        wholeDevice: wholeDevice,
        isFromDiskImage: isFromDiskImage,
        name: disk.name,
        icon: disk.icon,
        isMounted: disk.isMounted,
      ),
    )
  }

  private func removeDisk(device: String) {
    guard let index = self.disks.firstIndex(where: { $0.device == device }) else {
      return
    }

    self.disks.remove(at: index)
  }

  private func updateDisk(device: String, disk: DisksModelDisk) {
    guard let model = self.disks.first(where: { $0.device == device }) else {
      return
    }

    model.name = disk.name
    model.icon = disk.icon
    model.isMounted = disk.isMounted
  }

  nonisolated private func handleAppear(device: String, session: DASession) async {
    guard let disk = DADiskCreateFromBSDName(nil, session, device) else {
      return
    }

    guard let disk = self.disk(disk: disk) else {
      return
    }

    let wholeDevice: String

    do {
      wholeDevice = try await self.wholeDevice(name: device)
    } catch {
      Logger.ui.error("\(error)")

      return
    }

    let isFromDiskImage: Bool

    do {
      isFromDiskImage = try await self.isDiskImage(device: wholeDevice)
    } catch {
      Logger.ui.error("\(error)")

      return
    }

    await self.addDisk(device: device, wholeDevice: wholeDevice, isFromDiskImage: isFromDiskImage, disk: disk)
  }

  private func handleDisappear(device: String) {
    self.removeDisk(device: device)
  }

  nonisolated private func handleDescriptionChange(device: String, session: DASession) async {
    guard let disk = DADiskCreateFromBSDName(nil, session, device) else {
      return
    }

    guard let disk = self.disk(disk: disk) else {
      return
    }

    await self.updateDisk(device: device, disk: disk)
  }

  nonisolated private func disk(disk: DADisk) -> DisksModelDisk? {
    let description = DADiskCopyDescription(disk) as! [AnyHashable: Any]

    if let isInternal = description[kDADiskDescriptionDeviceInternalKey],
       isInternal as! Bool {
      return nil
    }

    if let content = description[kDADiskDescriptionMediaContentKey],
       let id = UUID(uuidString: content as! String),
       id == .efiPartition {
      return nil
    }

    guard let volumeUUID = description[kDADiskDescriptionVolumeUUIDKey],
          let volumeName = description[kDADiskDescriptionVolumeNameKey] else {
      return nil
    }

    // https://developer.apple.com/documentation/foundation/nsuuid
    //
    //   The NSUUID class is not toll-free bridged with CoreFoundation’s CFUUID.
    let uuid = volumeUUID as! CFUUID
    let id = UUID(uuidString: CFUUIDCreateString(nil, uuid) as String)!
    let name = volumeName as! String

    guard let icon = self.icon(description: description) else {
      return nil
    }

    let isMounted = description[kDADiskDescriptionVolumePathKey] != nil
    let disk = DisksModelDisk(id: id, name: name, icon: icon, isMounted: isMounted)

    return disk
  }

  nonisolated private func icon(description: [AnyHashable: Any]) -> Image? {
    if let url = description[kDADiskDescriptionVolumePathKey] as? URL {
      return Image(nsImage: NSWorkspace.shared.icon(forFileAt: url))
    }

    // https://github.com/kainjow/Semulov/blob/2bca059cd43b8d42161511ef03a283c495f71dc1/SLDiskManager.m#L123-L132
    let mediaIcon = description[kDADiskDescriptionMediaIconKey] as! [AnyHashable: Any]
    let bundleID = mediaIcon[kCFBundleIdentifierKey] as! CFString
    let bundleResourceFile = mediaIcon[kIOBundleResourceFileKey] as! String
    let url = KextManagerCreateURLForBundleIdentifier(nil, bundleID).takeRetainedValue() as URL
    let bundle = Bundle(url: url)!
    let image = bundle.image(forResource: bundleResourceFile)!

    return Image(nsImage: image)
  }
}
