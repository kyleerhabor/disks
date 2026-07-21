//
//  DisksModel+AttachPassphrase.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/19/26.
//

import Foundation

enum DisksModelAttachPassphraseErrorCode {
  case process(any Error)
}

struct DisksModelAttachPassphraseError {
  let code: DisksModelAttachPassphraseErrorCode
}

extension DisksModelAttachPassphraseError: Error {}

extension DisksModel {
  func attach(imageAt url: URL, passphrase: String) async throws(DisksModelAttachPassphraseError) {
    try await self._attach(imageAt: url, passphrase: passphrase)
  }

  nonisolated private func _attach(imageAt url: URL, passphrase: String) async throws(DisksModelAttachPassphraseError) {
    do {
      try await self.process(
        executable: .hdiutil,
        arguments: ["attach", url.absoluteString, "-plist", "-stdinpass"],
        data: passphrase.data(using: .utf8)!,
      )
    } catch {
      throw DisksModelAttachPassphraseError(code: .process(error))
    }
  }
}
