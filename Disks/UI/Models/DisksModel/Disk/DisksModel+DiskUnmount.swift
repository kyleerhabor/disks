//
//  DisksModel+DiskUnmount.swift
//  Disks
//
//  Created by Kyle Erhabor on 8/3/26.
//

import AppKit
import DisksCoreDiskArbitration
import Foundation

enum DisksModelUnmountDiskDiskArbitrationErrorReason {
  case unknownDisk,
       unmount(UnmountDiskError)
}

struct DisksModelUnmountDiskDiskArbitrationError {
  let device: String
  let reason: DisksModelUnmountDiskDiskArbitrationErrorReason
}

enum DisksModelUnmountDiskErrorReason {
  case diskArbitration(DisksModelUnmountDiskDiskArbitrationError)
}

struct DisksModelUnmountDiskError {
  let reason: DisksModelUnmountDiskErrorReason
}

extension DisksModelUnmountDiskError: Error {}

extension DisksModel {
  func unmount(disk: DisksDriveDiskModel) async throws(DisksModelUnmountDiskError) {
    guard let d = DADiskCreateFromBSDName(nil, self.session!.session, disk.device) else {
      throw DisksModelUnmountDiskError(
        reason: .diskArbitration(DisksModelUnmountDiskDiskArbitrationError(device: disk.device, reason: .unknownDisk)),
      )
    }

    let description = DADiskCopyDescription(d) as! [CFString: Any]
    let url = description[kDADiskDescriptionVolumePathKey] as! URL

    do {
      try await Disks.unmount(disk: d)
    } catch {
      var defaultError: DisksModelUnmountDiskError {
        DisksModelUnmountDiskError(
          reason: .diskArbitration(DisksModelUnmountDiskDiskArbitrationError(device: disk.device, reason: .unmount(error))),
        )
      }

      switch error.reason {
        case let .dissenter(dissenter) where disks_da_err_get_code(dissenter.status) == EBUSY:
          guard let apps = self.applications(using: url) else {
            throw defaultError
          }

          self.unmountBusyDiskSceneBusyDisk = UnmountBusyDiskModel(disk: disk, apps: apps)
          self.isUnmountBusyDiskScenePresented = true
        default:
          throw defaultError
      }

      return
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

    let sorted = NSWorkspace.shared.runningApplications
      .filter { $0.bundleURL != nil }
      .sorted { a, b in
        a.bundleURL!.path.count < b.bundleURL!.path.count
      }

    var roots = [URL: NSRunningApplication]()

    for app in sorted {
      let url = app.bundleURL!
      var root = app
      var current = url

      while true {
        let next = current.deletingLastPathComponent().standardizedFileURL

        if next == current {
          break
        }

        if let found = roots[next] {
          root = found

          break
        }

        current = next
      }

      roots[url] = root
    }

    let names = buffer
      .compactMap { pid in
        guard let app = NSRunningApplication(processIdentifier: pid),
              let url = app.bundleURL else {
          return nil
        }

        return roots[url.standardizedFileURL]!
      }
      .reduce(into: [pid_t: NSRunningApplication]()) { result, app in
        result[app.processIdentifier] = app
      }
      .values
      .map { $0.localizedName! }
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

    return names
  }
}
