//
//  DiskArbitration.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/29/26.
//

import DiskArbitration

private class ActionContext {
  let continuation: CheckedContinuation<Void, any Error>

  init(continuation: CheckedContinuation<Void, any Error>) {
    self.continuation = continuation
  }
}

struct MountDiskDissenterError {
  let status: DAReturn
}

enum MountDiskErrorReason {
  case dissenter(MountDiskDissenterError)
}

struct MountDiskError {
  let reason: MountDiskErrorReason
}

extension MountDiskError: Error {}

struct UnmountDiskDissenterError {
  let status: DAReturn
}

enum UnmountDiskErrorReason {
  case dissenter(UnmountDiskDissenterError)
}

struct UnmountDiskError {
  let reason: UnmountDiskErrorReason
}

extension UnmountDiskError: Error {}

struct EjectDiskDissenterError {
  let status: DAReturn
}

enum EjectDiskErrorReason {
  case dissenter(EjectDiskDissenterError)
}

struct EjectDiskError {
  let reason: EjectDiskErrorReason
}

extension EjectDiskError: Error {}

func mount(disk: DADisk) async throws(MountDiskError) {
  do {
    try await withCheckedThrowingContinuation { continuation in
      let context = Unmanaged.passRetained(ActionContext(continuation: continuation)).toOpaque()
      DADiskMount(
        disk,
        nil,
        DADiskMountOptions(),
        { disk, dissenter, context in
          let context = Unmanaged<ActionContext>.fromOpaque(context!).takeRetainedValue()

          if let dissenter {
            context.continuation.resume(
              throwing: MountDiskError(reason: .dissenter(MountDiskDissenterError(status: DADissenterGetStatus(dissenter)))),
            )

            return
          }

          context.continuation.resume()
        },
        context,
      )
    }
  } catch let error as MountDiskError {
    throw error
  } catch {
    unreachable()
  }
}

func unmount(disk: DADisk) async throws(UnmountDiskError) {
  do {
    try await withCheckedThrowingContinuation { continuation in
      let context = Unmanaged.passRetained(ActionContext(continuation: continuation)).toOpaque()
      DADiskUnmount(
        disk,
        DADiskUnmountOptions(),
        { disk, dissenter, context in
          let context = Unmanaged<ActionContext>.fromOpaque(context!).takeRetainedValue()
          
          if let dissenter {
            context.continuation.resume(
              throwing: UnmountDiskError(
                reason: .dissenter(UnmountDiskDissenterError(status: DADissenterGetStatus(dissenter)))
              ),
            )

            return
          }

          context.continuation.resume()
        },
        context,
      )
    }
  } catch let error as UnmountDiskError {
    throw error
  } catch {
    unreachable()
  }
}

func eject(disk: DADisk) async throws(EjectDiskError) {
  do {
    try await withCheckedThrowingContinuation { continuation in
      let context = Unmanaged.passRetained(ActionContext(continuation: continuation)).toOpaque()
      DADiskEject(
        disk,
        DADiskEjectOptions(),
        { disk, dissenter, context in
          let context = Unmanaged<ActionContext>.fromOpaque(context!).takeRetainedValue()

          if let dissenter {
            context.continuation.resume(
              throwing: EjectDiskError(
                reason: .dissenter(EjectDiskDissenterError(status: DADissenterGetStatus(dissenter)))
              ),
            )

            return
          }

          context.continuation.resume()
        },
        context,
      )
    }
  } catch let error as EjectDiskError {
    throw error
  } catch {
    unreachable()
  }
}
