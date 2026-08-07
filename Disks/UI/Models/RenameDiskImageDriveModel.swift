//
//  RenameDiskImageDriveModel.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/29/26.
//

import Foundation

@Observable
@MainActor
class RenameDiskImageDriveModel {
  let pathName: String
  var name: String

  init(pathName: String, name: String) {
    self.pathName = pathName
    self.name = name
  }
}
