//
//  DisksModel+DiskImage.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/24/26.
//

import Foundation
import System

private struct DisksModelDiskImageInfoOutputImageSystemEntity {
  let devEntry: FilePath
}

extension DisksModelDiskImageInfoOutputImageSystemEntity: Decodable {
  enum CodingKeys: String, CodingKey {
    case devEntry = "dev-entry"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let entry = try container.decode(String.self, forKey: .devEntry)

    self.devEntry = FilePath(entry)
  }
}

private struct DisksModelDiskImageInfoOutputImage {
  let imagePath: FilePath
  let systemEntities: [DisksModelDiskImageInfoOutputImageSystemEntity]
}

extension DisksModelDiskImageInfoOutputImage: Decodable {
  enum CodingKeys: String, CodingKey {
    case imagePath = "image-path",
         systemEntities = "system-entities"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let imagePath = try container.decode(String.self, forKey: .imagePath)
    self.imagePath = FilePath(imagePath)
    self.systemEntities = try container.decode([DisksModelDiskImageInfoOutputImageSystemEntity].self, forKey: .systemEntities)
  }
}

private struct DisksModelDiskImageInfoOutput {
  let images: [DisksModelDiskImageInfoOutputImage]
}

extension DisksModelDiskImageInfoOutput: Decodable {}

enum DisksModelDiskImageInfoErrorReason {
  case hdiutil(any Error),
       notFound
}

struct DisksModelDiskImageInfoError {
  let reason: DisksModelDiskImageInfoErrorReason
}

extension DisksModelDiskImageInfoError: Error {}

struct DisksModelDiskImageInfo {
  let path: FilePath
}

extension DisksModel {
  func diskImage(rootDevice device: String) async throws(DisksModelDiskImageInfoError) -> DisksModelDiskImageInfo {
    let data: Data

    do {
      data = try await self.process(executable: .hdiutil, arguments: ["info", "-plist"], data: Data())
    } catch {
      throw DisksModelDiskImageInfoError(reason: .hdiutil(error))
    }

    let decoder = PropertyListDecoder()
    let output: DisksModelDiskImageInfoOutput

    do {
      output = try decoder.decode(DisksModelDiskImageInfoOutput.self, from: data)
    } catch {
      throw DisksModelDiskImageInfoError(reason: .hdiutil(error))
    }

    let device = FilePath.Component(device)!
    let entry = FilePath(root: "/", components: "dev", device)
    let outputImage = output.images.first { image in
      image.systemEntities.first!.devEntry == entry
    }

    guard let outputImage else {
      throw DisksModelDiskImageInfoError(reason: .notFound)
    }

    let image = DisksModelDiskImageInfo(path: outputImage.imagePath)

    return image
  }
}
