//
//  UnlockFailedScene.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/19/26.
//

import SwiftUI

struct UnlockFailedScene: Scene {
  @Environment(DisksModel.self) private var disks

  var body: some Scene {
    @Bindable var disks = self.disks

    AlertScene(Text(verbatim: "Unlock failed"), isPresented: $disks.isUnlockFailedScenePresented) {
      // Empty
    } message: {
      Text(verbatim: "Make sure you entered your password correctly.")
    }
    .dialogSeverity(.critical)
  }
}
