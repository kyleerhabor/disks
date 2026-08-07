//
//  UnlockDiskImageScene.swift
//  Disks
//
//  Created by Kyle Erhabor on 8/3/26.
//

import SwiftUI
import OSLog

struct UnlockDiskImageScene: Scene {
  @Environment(DisksModel.self) private var disks

  var body: some Scene {
    @Bindable var disks = self.disks

    AlertScene(
      Text(verbatim: "Unlock Disk Image"),
      isPresented: $disks.isUnlockDiskImageScenePresented,
      presenting: disks.unlockDiskImageSceneDiskImage,
    ) { image in
      @Bindable var image = image

      SecureField(text: $image.password, prompt: Text(verbatim: "Password")) {
        Text(verbatim: "Password:")
      }

      Button(role: .cancel) {
        Task {
          do {
            try await image.mounter.resume()
          } catch {
            Logger.ui.error("Could not attach disk image at URL '\(image.url.debugString)': \(error)")

            return
          }
        }
      } label: {
        Text(verbatim: "Cancel")
      }

      Button {
        Task {
          do {
            try await image.mounter.resume(password: image.password)
          } catch {
            Logger.ui.error("Could not attach disk image at URL '\(image.url.debugString)': \(error)")

            return
          }
        }
      } label: {
        Text(verbatim: "Unlock")
      }
      .disabled(image.password.isEmpty)
    } message: { image in
      Text(verbatim: "Enter the password to unlock the disk image “\(image.name)”.")
    }
  }

}
