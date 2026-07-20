//
//  DisksApp.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/16/26.
//

import SwiftUI

@main
struct DisksApp: App {
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate
  @State private var disks = DisksModel()
  @State private var isInserted = true

  var body: some Scene {
    AppScene()
      .environment(self.disks)
  }

  init() {
    self.delegate.disks = self.disks
  }
}
