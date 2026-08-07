//
//  DisksModel+DiskFinder.swift
//  Disks
//
//  Created by Kyle Erhabor on 8/2/26.
//

import AppKit
import Foundation

enum DisksModelFinderDiskErrorReason {
  case open(any Error)
}

struct DisksModelFinderDiskError {
  let reason: DisksModelFinderDiskErrorReason
}

extension DisksModelFinderDiskError: Error {}

extension DisksModel {
  func showFinder(disk: DisksDriveDiskModel) async throws(DisksModelFinderDiskError) {
    guard let disk = DADiskCreateFromBSDName(nil, self.session!.session, disk.device) else {
      return
    }

    let description = DADiskCopyDescription(disk) as! [CFString: Any]

    guard let volumePath = description[kDADiskDescriptionVolumePathKey] else {
      return
    }

    let url = volumePath as! URL

    do {
      try await NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
    } catch {
      throw DisksModelFinderDiskError(reason: .open(error))
    }
  }
}
