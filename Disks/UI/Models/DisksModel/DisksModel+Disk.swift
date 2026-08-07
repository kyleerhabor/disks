//
//  DisksModel+Disk.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/19/26.
//

import Foundation

extension URL {
  static let diskutil = Self(filePath: "/usr/sbin/diskutil", directoryHint: .notDirectory)
}
