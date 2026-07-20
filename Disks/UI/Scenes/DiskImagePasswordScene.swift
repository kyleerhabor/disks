//
//  DiskImagePasswordScene.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/19/26.
//

import SwiftUI
import OSLog

struct DiskImagePasswordScene: Scene {
  @Environment(DisksModel.self) private var disks
  @State private var password = ""

  var body: some Scene {
    @Bindable var disks = self.disks

    AlertScene(
      Text(verbatim: "Enter password"),
      isPresented: $disks.isDiskImageScenePresented,
      presenting: disks.diskImageSceneImage,
    ) { image in
      SecureField(text: $password, prompt: Text(verbatim: "Password")) {
        Text(verbatim: "Password:")
      }

      Button(role: .cancel) {
        self.password = ""
      } label: {
        Text(verbatim: "Cancel")
      }

      Button {
        let password = self.password
        self.password = ""

        Task {
          do {
            try await disks.attach(imageAt: image.url, passphrase: password)
          } catch {
            // We can technically parse stderr since it's stable, but I can't be asked.
            Logger.ui.error("Could not attach disk image at URL '\(image.url)' with passphrase: \(error)")

            disks.isUnlockFailedScenePresented = true

            return
          }

          do {
            try await disks.store(image: image, password: password)
          } catch {
            // We can technically parse stderr since it's stable, but I can't be asked.
            Logger.ui.error("Could not store disk image at URL '\(image.url)': \(error)")

            return
          }
        }
      } label: {
        Text(verbatim: "Unlock")
      }
      .disabled(self.password.isEmpty)
    } message: { image in
      Text(verbatim: "Enter the password to unlock the disk image “\(image.name)”.")
    }
  }
}
