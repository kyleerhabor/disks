//
//  DisksModel+Unmount.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/20/26.
//

import DiskArbitration
import Foundation

struct DisksModelUnmountFailedError {
  let status: DAReturn
}

enum DisksModelUnmountErrorCode {
  case process(any Error),
       unknownDisk,
       unmountFailed(DisksModelUnmountFailedError)
}

struct DisksModelUnmountError {
  let device: String
  let code: DisksModelUnmountErrorCode
}

extension DisksModelUnmountError: Error {}

private struct DisksModelUnmountActionError {
  let status: DAReturn
}

extension DisksModelUnmountActionError: Error {}

private class DisksModelUnmountActionContext {
  let continuation: CheckedContinuation<Void, any Error>

  init(continuation: CheckedContinuation<Void, any Error>) {
    self.continuation = continuation
  }
}

extension DisksModel {
  func unmount(disk: DiskGroupItemModel) async throws(DisksModelUnmountError) {
    let session = self.session!
    try await self.unmount(device: disk.device, session: session.session)
  }

  func unmount(diskFromDiskImage disk: DiskGroupItemModel) async throws(DisksModelUnmountError) {
    let session = self.session!
    try await self.unmount(device: disk.device, session: session.session)

    let group = self.diskImageGroups.first { group in
      group.items.contains { $0.id == disk.id }
    }!

    guard group.items.allSatisfy({ $0.id == disk.id || !$0.isMounted }) else {
      return
    }

    let wholeDevice = self.disks[disk.device]!.wholeDevice
    try await self.detach(device: wholeDevice)
  }


  nonisolated private func unmount(device: String, session: DASession) async throws(DisksModelUnmountError) {
    guard let disk = DADiskCreateFromBSDName(nil, session, device) else {
      throw DisksModelUnmountError(device: device, code: .unknownDisk)
    }

    let description = DADiskCopyDescription(disk) as! [AnyHashable: Any]

    if description[kDADiskDescriptionVolumePathKey] == nil {
      // Already unmounted
      return
    }

    do {
      try await withCheckedThrowingContinuation { continuation in
        let context = Unmanaged.passRetained(DisksModelUnmountActionContext(continuation: continuation)).toOpaque()
        DADiskUnmount(
          disk,
          DADiskUnmountOptions(kDADiskUnmountOptionDefault),
          { disk, dissenter, context in
            let context = Unmanaged<DisksModelUnmountActionContext>.fromOpaque(context!).takeRetainedValue()

            if let dissenter {
              context.continuation.resume(throwing: DisksModelUnmountActionError(status: DADissenterGetStatus(dissenter)))

              return
            }

            context.continuation.resume()
          },
          context,
        )
      }
    } catch let error as DisksModelUnmountActionError {
      // TODO: Handle status 49168 (process with files open)
      throw DisksModelUnmountError(
        device: device,
        code: .unmountFailed(DisksModelUnmountFailedError(status: error.status)),
      )
    } catch {
      unreachable()
    }
  }

  nonisolated private func detach(device: String) async throws(DisksModelUnmountError) {
    do {
      try await self.process(
        executable: .hdiutil,
        arguments: ["detach", device],
        data: Data(),
      )
    } catch {
      throw DisksModelUnmountError(device: device, code: .process(error))
    }
  }
}
