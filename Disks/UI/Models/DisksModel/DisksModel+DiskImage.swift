//
//  DisksModel+DiskImage.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/19/26.
//

import Foundation

extension URL {
  static let hdiutil = Self(filePath: "/usr/bin/hdiutil", directoryHint: .notDirectory)
}

extension DisksModel {
  nonisolated static let diskImagePasswordService = "\(Bundle.appID).disk-image-password"
}
