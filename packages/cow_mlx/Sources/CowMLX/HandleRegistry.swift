import Foundation

/// Thread-safe registry mapping integer handles to Swift objects.
/// Handles are stable int32 indices that can safely cross the C/Dart boundary.
final class HandleRegistry<T: AnyObject>: @unchecked Sendable {
    private var storage: [Int32: T] = [:]
    private var nextHandle: Int32 = 0
    private let lock = NSLock()

    /// Insert a value and return its handle.
    func insert(_ value: T) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        let handle = nextHandle
        nextHandle += 1
        storage[handle] = value
        return handle
    }

    /// Look up a value by handle.
    func get(_ handle: Int32) -> T? {
        lock.lock()
        defer { lock.unlock() }
        return storage[handle]
    }

    /// Remove and return a value by handle.
    @discardableResult
    func remove(_ handle: Int32) -> T? {
        lock.lock()
        defer { lock.unlock() }
        return storage.removeValue(forKey: handle)
    }
}
