//
//  UnlockFailureDiskImageScene.swift
//  Disks
//
//  Created by Kyle Erhabor on 8/3/26.
//

import SwiftUI

struct UnlockFailureDiskImageScene: Scene {
  @Environment(DisksModel.self) private var disks

  var body: some Scene {
    @Bindable var disks = self.disks

    AlertScene(
      Text(verbatim: "Could Not Unlock Disk Image"),
      isPresented: $disks.isUnlockFailureDiskImageScenePresented,
      presenting: disks.unlockFailureDiskImageSceneDiskImage,
    ) { _ in
      // Empty
    } message: { image in
      Text("The disk image “\(image.name)” couldn't be unlocked. Make sure you entered the password correctly.")
    }
    .dialogSeverity(.critical)
  }
}

