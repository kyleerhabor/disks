//
//  UnlockFailureDiskScene.swift
//  Disks
//
//  Created by Kyle Erhabor on 8/2/26.
//

import SwiftUI

struct UnlockFailureDiskScene: Scene {
  @Environment(DisksModel.self) private var disks

  var body: some Scene {
    @Bindable var disks = self.disks

    AlertScene(
      Text(verbatim: "Could Not Unlock Disk"),
      isPresented: $disks.isUnlockFailureDiskScenePresented,
      presenting: disks.unlockFailureDiskSceneDisk,
    ) { _ in
      // Empty
    } message: { disk in
      Text("The disk “\(disk.disk.name)” couldn't be unlocked. Make sure you entered the password correctly.")
    }
    .dialogSeverity(.critical)
  }
}

