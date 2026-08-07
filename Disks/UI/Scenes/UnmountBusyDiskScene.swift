//
//  UnmountBusyDiskScene.swift
//  Disks
//
//  Created by Kyle Erhabor on 8/2/26.
//

import SwiftUI

struct UnmountBusyDiskScene: Scene {
  @Environment(DisksModel.self) private var disks

  var body: some Scene {
    @Bindable var disks = self.disks

    AlertScene(
      Text(verbatim: "Could Not Unmount Disk"),
      isPresented: $disks.isUnmountBusyDiskScenePresented,
      presenting: disks.unmountBusyDiskSceneBusyDisk,
    ) { _ in
      // Empty
    } message: { busy in
      Text("The disk “\(busy.disk.name)” is being used by \(Text(busy.apps, format: .list(type: .and, width: .standard))).")
    }
    .dialogSeverity(.critical)
  }
}
