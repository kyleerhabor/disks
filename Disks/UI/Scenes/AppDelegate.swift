//
//  AppDelegate.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/16/26.
//

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
  var disks: DisksModel!

  func applicationDidFinishLaunching(_ notification: Notification) {
    self.disks.start()
  }

  func applicationWillTerminate(_ notification: Notification) {
    self.disks.stop()
  }
}
