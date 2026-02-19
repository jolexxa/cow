import Foundation

/// Thread-keyed error string storage for the C API.
///
/// Each thread gets its own error buffer. After any C function returns
/// an error indicator, the caller can retrieve the message via
/// `cow_mlx_get_error()`.
enum ErrorState {
    nonisolated(unsafe) private static var errors: [ObjectIdentifier: String] = [:]
    private static let lock = NSLock()

    /// Set the error message for the calling thread.
    static func set(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        errors[ObjectIdentifier(Thread.current)] = message
    }

    /// Get the error message for the calling thread, or nil.
    static func get() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return errors[ObjectIdentifier(Thread.current)]
    }

    /// Clear the error message for the calling thread.
    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        errors.removeValue(forKey: ObjectIdentifier(Thread.current))
    }
}

/// Per-thread buffer that keeps the error C string alive until the next call.
/// This avoids dangling pointers when returning `const char*` from C functions.
enum ErrorBuffer {
    nonisolated(unsafe) private static var buffers: [ObjectIdentifier: UnsafeMutablePointer<CChar>] = [:]
    private static let lock = NSLock()

    /// Store an error string and return a pointer valid until the next call
    /// from the same thread.
    static func store(_ message: String?) -> UnsafePointer<CChar>? {
        let tid = ObjectIdentifier(Thread.current)
        lock.lock()
        // Free previous buffer for this thread.
        if let old = buffers.removeValue(forKey: tid) {
            old.deallocate()
        }
        guard let message else {
            lock.unlock()
            return nil
        }
        let cStr = message.utf8CString
        let buf = UnsafeMutablePointer<CChar>.allocate(capacity: cStr.count)
        cStr.withUnsafeBufferPointer { src in
            buf.initialize(from: src.baseAddress!, count: cStr.count)
        }
        buffers[tid] = buf
        lock.unlock()
        return UnsafePointer(buf)
    }
}
