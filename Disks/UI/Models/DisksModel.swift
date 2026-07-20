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
import SwiftUI

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
  fileprivate(set) var name: String
  fileprivate(set) var icon: Image

  init(uuid: UUID, device: String, name: String, icon: Image) {
    self.uuid = uuid
    self.device = device
    self.name = name
    self.icon = icon
  }
}

extension DiskModel: Identifiable {}

private struct DisksModelDisk {
  let id: UUID
  let name: String
  let icon: Image
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


  func start() {
    guard let s = DASessionCreate(nil) else {
      fatalError()
    }

    let queue = DispatchQueue(
      label: "\(Bundle.appID).disk-arbitration",
      target: .global(qos: .default),
    )

    let session = DiskSession(session: s, queue: queue)
    let context = Unmanaged.passUnretained(self).toOpaque()

    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0302-concurrent-value-and-concurrent-closures.md
    //
    //   C function pointers conform to the Sendable protocol. This is safe because they cannot capture values.

    let appeared = DiskAppearedAction(context: context) { disk, context in
      let model = Unmanaged<DisksModel>.fromOpaque(context!).takeUnretainedValue()
      model.handleAppear(disk)
    }

    DARegisterDiskAppearedCallback(session.session, nil, appeared.callback, appeared.context)

    let disappeared = DiskDisappearedAction(context: context) { disk, context in
      let model = Unmanaged<DisksModel>.fromOpaque(context!).takeUnretainedValue()
      model.handleDisappear(disk)
    }

    DARegisterDiskDisappearedCallback(session.session, nil, disappeared.callback, disappeared.context)

    let descriptionChanged = DiskDescriptionChangedAction(context: context) { disk, keys, context in
      let model = Unmanaged<DisksModel>.fromOpaque(context!).takeUnretainedValue()
      model.handleDescriptionChange(disk, keys: keys)
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

    self.session = nil
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

  private func addDisk(name: String, disk: DisksModelDisk) {
    self.disks.append(DiskModel(uuid: disk.id, device: name, name: disk.name, icon: disk.icon))
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
  }

  nonisolated private func handleAppear(_ disk: DADisk) {
    guard let name = self.deviceName(disk: disk),
          let disk = self.disk(disk: disk) else {
      return
    }

    Task { @MainActor in
      self.addDisk(name: name, disk: disk)
    }
  }

  nonisolated private func handleDisappear(_ disk: DADisk) {
    guard let name = self.deviceName(disk: disk) else {
      return
    }

    Task { @MainActor in
      self.removeDisk(device: name)
    }
  }

  nonisolated private func handleDescriptionChange(_ disk: DADisk, keys: CFArray) {
    guard let name = self.deviceName(disk: disk),
          let disk = self.disk(disk: disk) else {
      return
    }

    Task { @MainActor in
      self.updateDisk(device: name, disk: disk)
    }
  }

  nonisolated private func deviceName(disk: DADisk) -> String? {
    // This is nil on {id = /System/Volumes/Data/home?owner=0}
    guard let bsdName = DADiskGetBSDName(disk) else {
      return nil
    }

    let name = String(cString: bsdName)

    return name
  }

  nonisolated private func disk(disk: DADisk) -> DisksModelDisk? {
    let description = DADiskCopyDescription(disk) as! [AnyHashable: Any]

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

    let disk = DisksModelDisk(id: id, name: name, icon: icon)

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
