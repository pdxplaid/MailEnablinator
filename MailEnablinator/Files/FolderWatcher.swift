import CoreServices
import Foundation

// Wraps FSEventStream to watch a directory and yield on an AsyncStream.
// All mutable state is nonisolated(unsafe); callers must ensure start/stop
// are serialized (the DestinationCuller actor provides that guarantee).
final class FolderWatcher: @unchecked Sendable {
    nonisolated(unsafe) private var eventStream: FSEventStreamRef?
    nonisolated(unsafe) private var continuation: AsyncStream<Void>.Continuation?
    nonisolated(unsafe) private let fsQueue = DispatchQueue(
        label: "com.plaidapps.MailEnablinator.fsevents",
        qos: .utility
    )
    nonisolated(unsafe) let changes: AsyncStream<Void>

    nonisolated init() {
        var cont: AsyncStream<Void>.Continuation!
        changes = AsyncStream<Void> { cont = $0 }
        continuation = cont
    }

    nonisolated func start(url: URL) {
        stop()
        let path = url.path(percentEncoded: false)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var ctx = FSEventStreamContext(
            version: 0, info: selfPtr, retain: nil, release: nil, copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().continuation?.yield()
        }
        guard let ref = FSEventStreamCreate(
            nil, callback, &ctx,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,   // 1-second coalescing latency
            flags
        ) else { return }
        FSEventStreamSetDispatchQueue(ref, fsQueue)
        FSEventStreamStart(ref)
        eventStream = ref
    }

    nonisolated func stop() {
        guard let ref = eventStream else { return }
        FSEventStreamStop(ref)
        FSEventStreamInvalidate(ref)
        FSEventStreamRelease(ref)
        eventStream = nil
    }

    deinit {
        stop()
        continuation?.finish()
    }
}
