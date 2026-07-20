//
//  AppScene.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/17/26.
//

import SwiftUI

struct AppScene: Scene {
  var body: some Scene {
    DisksScene()

    // TODO: Display disk icon in secondary position.
    //
    // This requires using NSAlert.
    DiskPasswordScene()
    DiskImagePasswordScene()
    
    UnlockFailedScene()
  }
}
