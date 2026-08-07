//
//  UnmountBusyDiskModel.swift
//  Disks
//
//  Created by Kyle Erhabor on 8/2/26.
//

import Foundation

@Observable
@MainActor
class UnmountBusyDiskModel {
  let disk: DisksDriveDiskModel
  let apps: [String]

  init(disk: DisksDriveDiskModel, apps: [String]) {
    self.disk = disk
    self.apps = apps
  }
}
