//
//  DiskDriveView.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/29/26.
//

import SwiftUI
import OSLog

struct DiskDriveView: View {
  @Environment(DisksModel.self) private var disks
  let drive: DisksDriveModel

  var body: some View {
    Menu(self.drive.name) {
      Section {
        ForEach(self.drive.disks) { disk in
          Menu {
            Section {
              Button {
                Task {
                  await self.showFinder(disk: disk)
                }
              } label: {
                Text(verbatim: "Show in Finder")
              }
              .disabled(!disk.isMounted)
            }
          } label: {
            Label {
              Text(disk.name)
                .foregroundStyle(disk.isMounted ? .primary : .secondary)
            } icon: {
              disk.icon
            }
            .labelStyle(.titleAndIcon)
          } primaryAction: {
            Task {
              if disk.isMounted {
                await self.unmount(disk: disk)
              } else {
                await self.mount(disk: disk)
              }
            }
          }
        }
      }

      if self.drive.source == .disk {
        Section {
          Button {
            self.disks.presentRenameDriveScene(drive: self.drive)
          } label: {
            Text(verbatim: "Rename...")
          }
        }
      }

      Section {
        Button {
          Task {
            if self.drive.isMounted {
              await self.unmount(drive: self.drive)
            } else {
              await self.mount(drive: self.drive)
            }
          }
        } label: {
          Text(verbatim: self.drive.isMounted ? "Unmount" : "Mount")
        }

        Button {
          Task {
            await self.eject(drive: self.drive)
          }
        } label: {
          Text(verbatim: "Eject")
        }
      }
    }
  }

  // MARK: Drive

  private func mount(drive: DisksDriveModel) async {
    do {
      try await self.disks.mount(drive: drive)
    } catch {
      Logger.ui.error("Could not mount disk drive: \(error)")
    }
  }

  private func unmount(drive: DisksDriveModel) async {
    do {
      try await self.disks.unmount(drive: drive)
    } catch {
      Logger.ui.error("Could not unmount disk drive: \(error)")
    }
  }

  private func eject(drive: DisksDriveModel) async {
    do {
      try await self.disks.unmount(drive: drive)
    } catch {
      Logger.ui.error("Could not unmount disk drive: \(error)")
    }

    do {
      try await self.disks.eject(drive: drive)
    } catch {
      Logger.ui.error("Could not eject disk drive: \(error)")
    }
  }

  // MARK: Disk

  private func mount(disk: DisksDriveDiskModel) async {
    do {
      try await self.disks.mount(disk: disk)
    } catch {
      Logger.ui.error("Could not mount disk: \(error)")
    }
  }

  private func unmount(disk: DisksDriveDiskModel) async {
    do {
      try await self.disks.unmount(disk: disk)
    } catch {
      Logger.ui.error("Could not unmount disk: \(error)")
    }
  }

  private func showFinder(disk: DisksDriveDiskModel) async {
    do {
      try await self.disks.showFinder(disk: disk)
    } catch {
      Logger.ui.error("Could not show disk in Finder: \(error)")
    }
  }
}
