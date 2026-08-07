//
//  UnlockDiskModel.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/28/26.
//

import Observation

@Observable
@MainActor
class UnlockDiskModel {
  @ObservationIgnored var mounter: any DisksModelMounter
  let disk: DisksDriveDiskModel
  var password: String

  init(mounter: any DisksModelMounter, disk: DisksDriveDiskModel) {
    self.mounter = mounter
    self.disk = disk
    self.password = ""
  }
}
