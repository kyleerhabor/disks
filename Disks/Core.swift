//
//  Core.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/16/26.
//

import Foundation

func unreachable() -> Never {
  fatalError("Reached supposedly unreachable code")
}

// MARK: - Foundation

extension Bundle {
  static let appID = Bundle.main.bundleIdentifier!
}

extension URL {
  nonisolated var pathString: String {
    self.path(percentEncoded: false)
  }

  var debugString: String {
    let absoluteString = self.absoluteString
    let string = absoluteString.removingPercentEncoding ?? absoluteString

    return string
  }
}

// MARK: - Swift Concurrency

typealias AsyncStreamContinuationPair<Element> = (
  stream: AsyncStream<Element>,
  continuation: AsyncStream<Element>.Continuation,
)

// In some settings, calling a synchronous function from an asynchronous one can block the underlying cooperative thread,
// deadlocking the system when all cooperative threads are blocked (e.g., calling URL/bookmarkData(options:includingResourceValuesForKeys:relativeTo:)
// from a task group). I presume this is caused by a function:
//
//   1. Not being preconcurrency
//   2. Being I/O bound
//   3. Blocking a cooperative thread
//
// The solution, then, is to not block cooperative threads.
//
// See https://forums.swift.org/t/cooperative-pool-deadlock-when-calling-into-an-opaque-subsystem/70685
func schedule<T>(on queue: DispatchQueue, _ body: @escaping @Sendable () throws -> T) async throws -> T {
  try await withCheckedThrowingContinuation { continuation in
    queue.async {
      do {
        continuation.resume(returning: try body())
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }
}

// TODO: Evaluate name.
//
// This is called once, but really, it's called until it succeeds.
actor Once<Value, each Argument> where Value: Sendable {
  private let body: (repeat each Argument) async throws -> Value
  private var task: Task<Value, any Error>?

  init(_ body: @escaping (repeat each Argument) async throws -> Value) {
    self.body = body
  }

  func callAsFunction(_ args: repeat each Argument) async throws -> Value {
    if let task = self.task {
      return try await task.value
    }

    let task = Task {
      try await self.body(repeat each args)
    }

    self.task = task

    do {
      return try await task.value
    } catch {
      // Try again on the next call.
      self.task = nil

      throw error
    }
  }
}
