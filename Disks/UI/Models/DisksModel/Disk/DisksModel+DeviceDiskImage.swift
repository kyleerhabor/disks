//
//  DisksModel+DeviceDiskImage.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/20/26.
//

import Foundation
import System

private struct DisksModelDeviceDiskImageOutputImageSystemEntity {
  let devEntry: FilePath
}

extension DisksModelDeviceDiskImageOutputImageSystemEntity: Decodable {
  enum CodingKeys: String, CodingKey {
    case devEntry = "dev-entry"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let entry = try container.decode(String.self, forKey: .devEntry)

    self.devEntry = FilePath(entry)
  }
}

private struct DisksModelDeviceDiskImageOutputImage {
  let systemEntities: [DisksModelDeviceDiskImageOutputImageSystemEntity]
}

extension DisksModelDeviceDiskImageOutputImage: Decodable {
  enum CodingKeys: String, CodingKey {
    case systemEntities = "system-entities"
  }
}

private struct DisksModelDeviceDiskImageOutput {
  let images: [DisksModelDeviceDiskImageOutputImage]
}

extension DisksModelDeviceDiskImageOutput: Decodable {}

enum DisksModelDeviceDiskImageErrorCode {
  case process(any Error),
       decode(any Error)
}

struct DisksModelDeviceDiskImageError {
  let code: DisksModelDeviceDiskImageErrorCode
}

extension DisksModelDeviceDiskImageError: Error {}

extension DisksModel {
  nonisolated func isDiskImage(device: String) async throws(DisksModelDeviceDiskImageError) -> Bool {
    let data: Data

    do {
      data = try await self.process(executable: .hdiutil, arguments: ["info", "-plist"], data: Data())
    } catch {
      throw DisksModelDeviceDiskImageError(code: .process(error))
    }

    let decoder = PropertyListDecoder()
    let output: DisksModelDeviceDiskImageOutput

    do {
      output = try decoder.decode(DisksModelDeviceDiskImageOutput.self, from: data)
    } catch {
      throw DisksModelDeviceDiskImageError(code: .decode(error))
    }

    let device = FilePath.Component(device)!
    let entry = FilePath(root: "/", components: "dev", device)
    let isImage = output.images.contains { image in
      image.systemEntities.first!.devEntry == entry
    }

    return isImage
  }
}
