//
//  DisksView.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/16/26.
//

import AppKit
import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import OSLog

struct DisksView: View {
  @Environment(DisksModel.self) private var disks

  var body: some View {
    ForEach(self.disks.diskGroups) { group in
      Section(group.name) {
        ForEach(group.items) { item in
          Button {
            Task {
              if item.isMounted {
                await self.unmount(disk: item)
              } else {
                await self.mount(disk: item)
              }
            }
          } label: {
            Label {
              Text(item.name)
                .foregroundStyle(item.isMounted ? .primary : .secondary)
            } icon: {
              item.icon
            }
            .labelStyle(.titleAndIcon)
          }
        }
      }
    }

    ForEach(self.disks.diskImageGroups) { group in
      Section {
        ForEach(group.items) { item in
          Button {
            Task {
              if item.isMounted {
                await self.unmount(diskFromDiskImage: item)
              } else {
                await self.mount(disk: item)
              }
            }
          } label: {
            Label {
              Text(item.name)
                .foregroundStyle(item.isMounted ? .primary : .secondary)
            } icon: {
              item.icon
            }
            .labelStyle(.titleAndIcon)
          }
        }
      } header: {
        Text(verbatim: "Disk Image")
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
          await self.attach(imageAt: url)
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

  private func mount(disk: DiskGroupItemModel) async {
    let mount: DisksModelMount

    do {
      mount = try await self.disks.mount(disk: disk)
    } catch {
      Logger.ui.error("Could not mount disk: \(error)")

      return
    }

    switch mount {
      case .ok:
        break
      case .encrypted:
        let model = DiskModel(uuid: disk.uuid, device: disk.device, name: disk.name)
        let password: String

        do {
          password = try await self.disks.loadPassword(disk: disk)
        } catch {
          Logger.ui.error("Could not load password for disk: \(error)")

          self.disks.diskSceneDisk = model
          self.disks.isDiskScenePresented = true

          return
        }

        do {
          try await self.disks.mount(disk: model, passphrase: password)
        } catch let error {
          Logger.ui.error("Could not mount disk with passphrase: \(error)")

          self.disks.diskSceneDisk = model
          self.disks.isDiskScenePresented = true

          return
        }
    }
  }

  private func unmount(disk: DiskGroupItemModel) async {
    do {
      try await self.disks.unmount(disk: disk)
    } catch {
      Logger.ui.error("Could not unmount disk: \(error)")

      return
    }
  }

  private func unmount(diskFromDiskImage disk: DiskGroupItemModel) async {
    do {
      try await self.disks.unmount(diskFromDiskImage: disk)
    } catch {
      Logger.ui.error("Could not unmount disk from disk image: \(error)")

      return
    }
  }

  private func attach(imageAt url: URL) async {
    let attach: DisksModelAttach

    do {
      attach = try await self.disks.attach(imageAt: url)
    } catch {
      Logger.ui.error("Could not attach disk image at URL '\(url.debugString)': \(error)")

      return
    }

    switch attach {
      case .ok:
        break
      case let .encrypted(encrypted):
        let resourceValues: URLResourceValues

        do {
          resourceValues = try url.resourceValues(forKeys: [.localizedNameKey])
        } catch {
          Logger.ui.error("Could not fetch resource values for disk image at URL '\(url.debugString)': \(error)")

          return
        }

        let name = resourceValues.localizedName!
        let image = DiskImageModel(uuid: encrypted.id, name: name, url: url)
        let password: String

        do {
          password = try await self.disks.loadPassword(image: image)
        } catch {
          Logger.ui.error("Could not load password for disk image '\(image.uuid)' at URL '\(url.debugString)': \(error)")

          self.disks.diskImageSceneImage = image
          self.disks.isDiskImageScenePresented = true

          return
        }

        do {
          try await self.disks.attach(imageAt: image.url, passphrase: password)
        } catch {
          Logger.ui.error("Could not attach disk image at URL '\(image.url)' with passphrase: \(error)")

          self.disks.diskImageSceneImage = image
          self.disks.isDiskImageScenePresented = true

          return
        }
    }
  }
}

#Preview {
  DisksView()
}
