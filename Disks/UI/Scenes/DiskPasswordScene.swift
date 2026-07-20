//
//  DiskPasswordScene.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/19/26.
//

import SwiftUI
import OSLog

struct DiskPasswordScene: Scene {
  @Environment(DisksModel.self) private var disks
  @State private var password = ""

  var body: some Scene {
    @Bindable var disks = self.disks

    AlertScene(
      Text(verbatim: "Enter password"),
      isPresented: $disks.isDiskScenePresented,
      presenting: disks.diskSceneDisk,
    ) { disk in
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
            try await disks.mount(disk: disk, passphrase: password)
          } catch let error as DisksModelMountPassphraseError {
            switch error.code {
              case .notSuccessful:
                break
              default:
                Logger.ui.error("Could not mount disk with passphrase: \(error)")
            }

            disks.isUnlockFailedScenePresented = true

            return
          }

          do {
            try await disks.store(disk: disk, password: password)
          } catch {
            Logger.ui.error("Could not store disk: \(error)")

            disks.isUnlockFailedScenePresented = true

            return
          }
        }
      } label: {
        Text(verbatim: "Unlock")
      }
      .disabled(self.password.isEmpty)
    } message: { disk in
      Text(verbatim: "Enter the password to unlock the disk “\(disk.name)”.")
    }
  }
}
