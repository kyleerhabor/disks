//
//  Process.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/28/26.
//

import Foundation

enum ProcessErrorReason {
  case pipe(any Error),
       run(any Error)
}

struct ProcessError {
  let reason: ProcessErrorReason
}

extension ProcessError: Error {}

struct ProcessOutput {
  let output: Data?
  let error: Data?
  let exitStatus: Int32
}

extension Process {
  static func run(
    executable: URL,
    arguments: [String],
    input: some DataProtocol = Data(),
  ) async throws(ProcessError) -> ProcessOutput {
    do {
      return try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let stdin = Pipe()
        process.standardInput = stdin

        let stdout = Pipe()
        process.standardOutput = stdout

        let stderr = Pipe()
        process.standardError = stderr
        process.terminationHandler = { process in
          let output: Data?

          do {
            output = try stdout.fileHandleForReading.readToEnd()
          } catch {
            continuation.resume(throwing: ProcessError(reason: .pipe(error)))

            return
          }

          let error: Data?

          do {
            error = try stderr.fileHandleForReading.readToEnd()
          } catch {
            continuation.resume(throwing: ProcessError(reason: .pipe(error)))

            return
          }

          continuation.resume(
            returning: ProcessOutput(output: output, error: error, exitStatus: process.terminationStatus),
          )
        }

        do {
          try process.run()
        } catch {
          continuation.resume(throwing: ProcessError(reason: .run(error)))

          return
        }

        do {
          try stdin.fileHandleForWriting.write(contentsOf: input)
        } catch {
          continuation.resume(throwing: ProcessError(reason: .pipe(error)))

          return
        }

        do {
          try stdin.fileHandleForWriting.close()
        } catch {
          continuation.resume(throwing: ProcessError(reason: .pipe(error)))

          return
        }
      }
    } catch let error as ProcessError {
      throw error
    } catch {
      unreachable()
    }
  }
}
