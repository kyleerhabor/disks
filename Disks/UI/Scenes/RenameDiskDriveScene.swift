//
//  RenameDiskDriveScene.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/24/26.
//

import OSLog
import SwiftUI

struct RenameDiskDriveScene: Scene {
  @Environment(DisksModel.self) private var disks

  var body: some Scene {
    @Bindable var disks = self.disks

    AlertScene(
      Text(verbatim: "Rename External Drive"),
      isPresented: $disks.isRenameDiskDriveScenePresented,
      presenting: disks.renameDiskDriveSceneDrive,
    ) { drive in
      @Bindable var drive = drive

      TextField(text: $drive.name, prompt: Text(drive.originalName)) {
        Text(verbatim: "Name:")
      }

      Button(role: .cancel) {
        // Empty
      } label: {
        Text(verbatim: "Cancel")
      }

      Button {
        Task {
          do {
            try await self.disks.rename(resuming: drive.continuation, name: drive.name)
          } catch {
            Logger.ui.error("\(error)")
          }
        }
      } label: {
        Text(verbatim: "Rename")
      }
    } message: { drive in
      Text(verbatim: "Enter a name for the external drive “\(drive.originalName)”.")
    }
  }
}
