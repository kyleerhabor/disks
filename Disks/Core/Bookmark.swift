//
//  Bookmark.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/18/26.
//

import Foundation
import OSLog

extension Logger {
  static let bookmark = Self(subsystem: Bundle.appID, category: "Bookmark")
}

extension URL {
  func startSecurityScope() -> Bool {
    let isAccessing = self.startAccessingSecurityScopedResource()

    if isAccessing {
      Logger.bookmark.debug("Started security scope for resource at URL '\(self.debugString)'")
    } else {
      Logger.bookmark.log("Could not start security scope for resource at URL '\(self.debugString)'")
    }

    return isAccessing
  }

  func endSecurityScope() {
    self.stopAccessingSecurityScopedResource()
    Logger.bookmark.debug("Ended security scope for resource at URL '\(self.debugString)'")
  }
}

protocol SecurityScopedResource {
  associatedtype SecurityScope

  func startSecurityScope() -> SecurityScope

  func endSecurityScope(_ scope: SecurityScope)
}

extension SecurityScopedResource {
  func accessingSecurityScopedResource<R, E>(_ body: () throws(E) -> R) throws(E) -> R {
    let scope = self.startSecurityScope()

    defer {
      self.endSecurityScope(scope)
    }

    return try body()
  }
}

extension URL: SecurityScopedResource {
  func endSecurityScope(_ scope: Bool) {
    guard scope else {
      return
    }

    self.endSecurityScope()
  }
}

struct URLSource {
  let url: URL
  // TODO: Consider whether or not to use URL.BookmarkResolutionOptions
//  let options: URL.BookmarkCreationOptions
  let options: URL.BookmarkResolutionOptions
}

extension URLSource: Equatable {}

extension URLSource: Hashable {
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.url)
    hasher.combine(self.options.rawValue)
  }
}

extension URLSource: SecurityScopedResource {
  func startSecurityScope() -> Bool {
    self.options.contains(.withSecurityScope) && self.url.startSecurityScope()
  }

  func endSecurityScope(_ scope: Bool) {
    self.url.endSecurityScope(scope)
  }
}

struct URLSourceDocument {
  let source: URLSource
  let relative: URLSource?
}

extension URLSourceDocument: SecurityScopedResource {
  struct SecurityScope {
    let source: URLSource.SecurityScope
    let relative: URLSource.SecurityScope?
  }

  func startSecurityScope() -> SecurityScope {
    let relative = self.relative?.startSecurityScope()
    let source = self.source.startSecurityScope()
    let scope = SecurityScope(source: source, relative: relative)

    return scope
  }

  func endSecurityScope(_ scope: SecurityScope) {
    self.source.endSecurityScope(scope.source)

    guard let scope = scope.relative else {
      return
    }

    self.relative!.endSecurityScope(scope)
  }
}
