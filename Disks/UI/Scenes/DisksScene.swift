//
//  DisksScene.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/16/26.
//

import SwiftUI
import GRDB

struct DisksScene: Scene {
  @Environment(DisksModel.self) private var disks
  // This prevents the app from quitting after the user removes it from the menu bar.
  @State private var isInserted = true

  var body: some Scene {
    MenuBarExtra(isInserted: $isInserted) {
      DisksView()
        .environment(self.disks)
    } label: {
      Label {
        Text(verbatim: "Disks")
      } icon: {
        Image(systemName: "externaldrive")
      }
    }
  }
}
