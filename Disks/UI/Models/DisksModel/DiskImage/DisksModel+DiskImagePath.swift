//
//  DisksModel+DiskImagePath.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/24/26.
//

import Foundation
import System

private struct InfoImageSystemEntityProcessOutput {
  let devEntry: FilePath
}

extension InfoImageSystemEntityProcessOutput: Decodable {
  enum CodingKeys: String, CodingKey {
    case devEntry = "dev-entry"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let entry = try container.decode(String.self, forKey: .devEntry)

    self.devEntry = FilePath(entry)
  }
}

private struct InfoImageProcessOutput {
  let imagePath: FilePath
  let systemEntities: [InfoImageSystemEntityProcessOutput]
}

extension InfoImageProcessOutput: Decodable {
  enum CodingKeys: String, CodingKey {
    case imagePath = "image-path",
         systemEntities = "system-entities"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let imagePath = try container.decode(String.self, forKey: .imagePath)
    self.imagePath = FilePath(imagePath)
    self.systemEntities = try container.decode([InfoImageSystemEntityProcessOutput].self, forKey: .systemEntities)
  }
}

private struct InfoProcessOutput {
  let images: [InfoImageProcessOutput]
}

extension InfoProcessOutput: Decodable {}

struct DisksModelDiskImagePathBadProcessExitError {
  let status: Int32
}

enum DisksModelDiskImagePathErrorReason {
  case process(any Error),
       badProcessExit(DisksModelDiskImagePathBadProcessExitError),
       badProcessOutput,
       notFound
}

struct DisksModelDiskImagePathError {
  let reason: DisksModelDiskImagePathErrorReason
}

extension DisksModelDiskImagePathError: Error {}

extension DisksModel {
  func diskImagePath(rootDevice device: String) async throws(DisksModelDiskImagePathError) -> FilePath {
    let output: ProcessOutput

    do {
      output = try await Process.run(executable: .hdiutil, arguments: ["info", "-plist"])
    } catch {
      throw DisksModelDiskImagePathError(reason: .process(error))
    }

    guard output.exitStatus == 0 else {
      throw DisksModelDiskImagePathError(
        reason: .badProcessExit(DisksModelDiskImagePathBadProcessExitError(status: output.exitStatus)),
      )
    }

    let decoder = PropertyListDecoder()
    let decoded: InfoProcessOutput

    do {
      decoded = try decoder.decode(InfoProcessOutput.self, from: output.output!)
    } catch {
      throw DisksModelDiskImagePathError(reason: .badProcessOutput)
    }

    let device = FilePath.Component(device)!
    let entry = FilePath(root: "/", components: "dev", device)
    let image = decoded.images.first { image in
      image.systemEntities.first!.devEntry == entry
    }

    guard let image else {
      throw DisksModelDiskImagePathError(reason: .notFound)
    }

    let path = image.imagePath

    return path
  }
}
