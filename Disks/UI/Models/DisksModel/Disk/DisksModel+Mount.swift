//
//  DisksModel+Mount.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/19/26.
//

import DiskArbitration
import Foundation

enum DisksModelMount {
  case ok, encrypted
}

struct DisksModelMountFailedError {
  let status: DAReturn
}

enum DisksModelMountErrorCode {
  case unknownDisk,
       mountFailed(DisksModelMountFailedError)
}

struct DisksModelMountError {
  let device: String
  let code: DisksModelMountErrorCode
}

extension DisksModelMountError: Error {}

private struct DisksModelMountActionError {
  let status: DAReturn
}

extension DisksModelMountActionError: Error {}

private class DisksModelMountActionContext {
  let continuation: CheckedContinuation<Void, any Error>

  init(continuation: CheckedContinuation<Void, any Error>) {
    self.continuation = continuation
  }
}

extension DisksModel {
  func mount(disk: DiskModel) async throws(DisksModelMountError) -> DisksModelMount {
    let session = self.session!
    let mount = try await self.mount(device: disk.device, session: session.session)

    return mount
  }

  nonisolated private func mount(
    device: String,
    session: DASession,
  ) async throws(DisksModelMountError) -> DisksModelMount {
    guard let disk = DADiskCreateFromBSDName(nil, session, device) else {
      throw DisksModelMountError(device: device, code: .unknownDisk)
    }

    let description = DADiskCopyDescription(disk) as! [AnyHashable: Any]

    if description[kDADiskDescriptionVolumePathKey] != nil {
      // Already mounted
      return .ok
    }

    if let encrypted = description[kDADiskDescriptionMediaEncryptedKey], encrypted as! Bool {
      return .encrypted
    }

    do {
      try await withCheckedThrowingContinuation { continuation in
        let context = Unmanaged.passRetained(DisksModelMountActionContext(continuation: continuation)).toOpaque()
        DADiskMount(
          disk,
          nil,
          DADiskMountOptions(kDADiskMountOptionDefault),
          { disk, dissenter, context in
            let context = Unmanaged<DisksModelMountActionContext>.fromOpaque(context!).takeRetainedValue()

            if let dissenter {
              context.continuation.resume(throwing: DisksModelMountActionError(status: DADissenterGetStatus(dissenter)))

              return
            }

            context.continuation.resume()
          },
          context,
        )
      }
    } catch let error as DisksModelMountActionError {
      throw DisksModelMountError(device: device, code: .mountFailed(DisksModelMountFailedError(status: error.status)))
    } catch {
      unreachable()
    }

    return .ok
  }
}
