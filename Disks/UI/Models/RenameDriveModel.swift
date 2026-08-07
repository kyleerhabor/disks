//
//  RenameDriveModel.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/29/26.
//

import Foundation

@Observable
@MainActor
class RenameDriveModel {
  let continuation: DisksDriveRenameDriveContinuation
  let originalName: String
  var name: String

  init(continuation: DisksDriveRenameDriveContinuation, originalName: String, name: String) {
    self.continuation = continuation
    self.originalName = originalName
    self.name = name
  }
}
