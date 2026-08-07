//
//  UnlockFailureDiskModel.swift
//  Disks
//
//  Created by Kyle Erhabor on 8/2/26.
//

import Foundation

@Observable
@MainActor
class UnlockFailureDiskModel {
  let disk: DisksDriveDiskModel

  init(disk: DisksDriveDiskModel) {
    self.disk = disk
  }
}
