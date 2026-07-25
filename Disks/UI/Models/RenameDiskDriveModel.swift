//
//  RenameDiskDriveModel.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/24/26.
//

import Foundation

@Observable
@MainActor
class RenameDiskDriveModel {
  @ObservationIgnored let device: String
  let mediaName: String
  var name: String

  init(device: String, mediaName: String, name: String) {
    self.device = device
    self.mediaName = mediaName
    self.name = name
  }
}
