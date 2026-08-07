//
//  UnlockDiskImageModel.swift
//  Disks
//
//  Created by Kyle Erhabor on 8/3/26.
//

import Foundation

@Observable
@MainActor
class UnlockDiskImageModel {
  let mounter: any DisksModelMounter
  let url: URL
  let name: String
  var password: String

  init(mounter: any DisksModelMounter, url: URL, name: String) {
    self.mounter = mounter
    self.url = url
    self.name = name
    self.password = ""
  }
}
