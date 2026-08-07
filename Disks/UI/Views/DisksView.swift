//
//  DisksView.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/16/26.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OSLog

struct DisksView: View {
  @Environment(DisksModel.self) private var disks
  
  var body: some View {
    if !self.disks.diskDrives.isEmpty {
      Section {
        ForEach(self.disks.diskDrives) { drive in
          DiskDriveView(drive: drive)
        }
      } header: {
        Text(verbatim: "External Drives")
      }
    }

    if !self.disks.diskImageDrives.isEmpty {
      Section {
        ForEach(self.disks.diskImageDrives) { drive in
          DiskDriveView(drive: drive)
        }
      } header: {
        Text(verbatim: "Disk Images")
      }
    }
    
    Section {
      Button {
        Task {
          let panel = NSOpenPanel()
          panel.allowedContentTypes = [.diskImage]
          panel.allowsMultipleSelection = false

          NSApp.activate(ignoringOtherApps: true)

          guard await panel.begin() == .OK else {
            return
          }

          let url = panel.url!
          await self.attach(diskImageAt: url)
        }
      } label: {
        Text(verbatim: "Open...")
      }
    }

    Section {
      Button {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel()
      } label: {
        Text(verbatim: "About Disks")
      }
    }

    Section {
      Button {
        NSApp.terminate(nil)
      } label: {
        Text(verbatim: "Quit Disks")
      }
    }
  }

  private func attach(diskImageAt url: URL) async {
    do {
      try await self.disks.attach(diskImageAt: url)
    } catch {
      Logger.ui.error("Could not attack disk image at URL '\(url.debugString)': \(error)")
    }
  }
}

#Preview {
  DisksView()
}
