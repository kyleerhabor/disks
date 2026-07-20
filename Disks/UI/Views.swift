//
//  Views.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/16/26.
//

import AppKit
import Foundation

extension NSWorkspace {
  nonisolated func icon(forFileAt url: URL) -> NSImage {
    self.icon(forFile: url.pathString)
  }
}
