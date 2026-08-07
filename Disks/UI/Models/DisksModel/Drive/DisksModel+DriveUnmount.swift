//
//  DisksModel+DriveUnmount.swift
//  Disks
//
//  Created by Kyle Erhabor on 8/2/26.
//

import AppKit
import Foundation
import DisksCoreDiskArbitration

struct DisksModelUnmountDriveUnmountDiskError {
  let device: String
  let underlyingError: UnmountDiskError
}

enum DisksModelUnmountDriveErrorReason {
  case unmountDisk(DisksModelUnmountDriveUnmountDiskError)
}

struct DisksModelUnmountDriveError {
  let reason: DisksModelUnmountDriveErrorReason
}

extension DisksModelUnmountDriveError: Error {}

extension DisksModel {
  func unmount(drive: DisksDriveModel) async throws(DisksModelUnmountDriveError) {
    let session = self.session!

    for disk in drive.disks {
      let device = disk.device

      guard let d = DADiskCreateFromBSDName(nil, session.session, device) else {
        continue
      }

      let description = DADiskCopyDescription(d) as! [CFString: Any]

      guard let volumePathValue = description[kDADiskDescriptionVolumePathKey] else {
        // Already unmounted
        continue
      }

      let volumePath = volumePathValue as! URL

      do {
        try await Disks.unmount(disk: d)
      } catch {
        var defaultError: DisksModelUnmountDriveError {
          DisksModelUnmountDriveError(
            reason: .unmountDisk(DisksModelUnmountDriveUnmountDiskError(device: device, underlyingError: error)),
          )
        }

        switch error.reason {
          case let .dissenter(dissenter) where disks_da_err_get_code(dissenter.status) == EBUSY:
            guard let apps = self.applications(using: volumePath) else {
              throw defaultError
            }

            self.unmountBusyDiskSceneBusyDisk = UnmountBusyDiskModel(disk: disk, apps: apps)
            self.isUnmountBusyDiskScenePresented = true
          default:
            throw defaultError
        }

        break
      }
    }
  }

  nonisolated private func applications(using url: URL) -> [String]? {
    // This is a private API, so it may be removed in the future.
    let type = UInt32(PROC_ALL_PIDS)
    let flags = UInt32(PROC_LISTPIDSPATH_PATH_IS_VOLUME)
    let buffer = url.withUnsafeFileSystemRepresentation { path -> [pid_t]? in
      let size = proc_listpidspath(type, 0, path, flags, nil, 0)

      guard size != -1 else {
        return nil
      }

      var buffer = [pid_t](repeating: 0, count: Int(size) / MemoryLayout<pid_t>.size)
      let used = proc_listpidspath(type, 0, path, flags, &buffer, size * Int32(MemoryLayout<pid_t>.size))

      guard used != -1 else {
        return nil
      }

      return buffer
    }

    guard let buffer else {
      return nil
    }

    let apps = buffer
      .compactMap { NSRunningApplication(processIdentifier: $0) }
      .map { $0.localizedName! }
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

    return apps
  }
}
