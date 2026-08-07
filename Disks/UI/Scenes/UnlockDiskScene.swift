//
//  UnlockDiskScene.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/28/26.
//

import OSLog
import SwiftUI

struct UnlockDiskScene: Scene {
  @Environment(DisksModel.self) private var disks

  var body: some Scene {
    @Bindable var disks = self.disks

    AlertScene(
      Text(verbatim: "Unlock Disk"),
      isPresented: $disks.isUnlockDiskScenePresented,
      presenting: disks.unlockDiskSceneDisk,
    ) { disk in
      @Bindable var disk = disk

      SecureField(text: $disk.password, prompt: Text(verbatim: "Password")) {
        Text(verbatim: "Password:")
      }

      Button(role: .cancel) {
        Task {
          do {
            try await disk.mounter.resume()
          } catch let error {
            Logger.ui.error("Could not mount: \(error)")

            return
          }
        }
      } label: {
        Text(verbatim: "Cancel")
      }

      Button {
        Task {
          do {
            try await disk.mounter.resume(password: disk.password)
          } catch let error {
            Logger.ui.error("Could not mount: \(error)")

            return
          }
        }
      } label: {
        Text(verbatim: "Unlock")
      }
      .disabled(disk.password.isEmpty)
    } message: { disk in
      Text(verbatim: "Enter the password to unlock the disk “\(disk.disk.name)”.")
    }
  }
}
