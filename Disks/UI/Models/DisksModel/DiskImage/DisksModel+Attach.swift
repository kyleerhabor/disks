//
//  DisksModel+Attach.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/19/26.
//

import Foundation
import System

struct DisksModelAttachEncrypted {
  let id: UUID
}

enum DisksModelAttach {
  case ok, encrypted(DisksModelAttachEncrypted)
}

struct DisksModelAttachBadOutputError {
  let data: Data
  let underlyingError: any Error
}

enum DisksModelAttachErrorCode {
  case process(any Error),
       badOutput(DisksModelAttachBadOutputError)
}

struct DisksModelAttachError {
  let code: DisksModelAttachErrorCode
}

extension DisksModelAttachError: Error {}

private struct DisksModelAttachInfoImageOutput {
  let path: FilePath
}

extension DisksModelAttachInfoImageOutput: Decodable {
  enum CodingKeys: String, CodingKey {
    case path = "image-path"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let path = try container.decode(String.self, forKey: .path)

    self.path = FilePath(path)
  }
}

private struct DisksModelAttachInfoOutput {
  let images: [DisksModelAttachInfoImageOutput]
}

extension DisksModelAttachInfoOutput: Decodable {}

private struct DisksModelAttachEncryptionOutput {
  let isEncrypted: Bool
  let id: UUID?
}

extension DisksModelAttachEncryptionOutput: Decodable {
  enum CodingKeys: String, CodingKey {
    case isEncrypted = "encrypted"
    case id = "uuid"
  }
}

extension DisksModel {
  func attach(imageAt url: URL) async throws(DisksModelAttachError) -> DisksModelAttach {
    try await self._attach(imageAt: url)
  }

  nonisolated private func _attach(imageAt url: URL) async throws(DisksModelAttachError) -> DisksModelAttach {
    let decoder = PropertyListDecoder()
    let infoData: Data

    do {
      infoData = try await self.process(executable: .hdiutil, arguments: ["info", "-plist"], data: Data())
    } catch {
      throw DisksModelAttachError(code: .process(error))
    }

    let info: DisksModelAttachInfoOutput

    do {
      info = try decoder.decode(DisksModelAttachInfoOutput.self, from: infoData)
    } catch {
      throw DisksModelAttachError(code: .badOutput(DisksModelAttachBadOutputError(data: infoData, underlyingError: error)))
    }

    let path = FilePath(url)!

    if info.images.contains(where: { $0.path == path }) {
      // Already attached
      return .ok
    }

    let encryptionData: Data

    do {
      encryptionData = try await self.process(
        executable: .hdiutil,
        arguments: ["isencrypted", url.absoluteString, "-plist"],
        data: Data(),
      )
    } catch {
      throw DisksModelAttachError(code: .process(error))
    }

    let encryption: DisksModelAttachEncryptionOutput

    do {
      encryption = try decoder.decode(DisksModelAttachEncryptionOutput.self, from: encryptionData)
    } catch {
      throw DisksModelAttachError(
        code: .badOutput(DisksModelAttachBadOutputError(data: encryptionData, underlyingError: error)),
      )
    }

    if encryption.isEncrypted {
      // Let's hope id is not nil.
      return .encrypted(DisksModelAttachEncrypted(id: encryption.id!))
    }

    do {
      try await self.process(
        executable: .hdiutil,
        arguments: ["attach", url.absoluteString, "-plist"],
        data: Data(),
      )
    } catch {
      throw DisksModelAttachError(code: .process(error))
    }

    return .ok
  }

}
