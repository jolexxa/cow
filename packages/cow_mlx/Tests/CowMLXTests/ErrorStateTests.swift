import Foundation
import Testing

@testable import CowMLX

@Suite("ErrorState")
struct ErrorStateTests {
    @Test("Set then get returns the message")
    func setThenGet() {
        ErrorState.set("test error")
        #expect(ErrorState.get() == "test error")
        ErrorState.clear()
    }

    @Test("Clear then get returns nil")
    func clearThenGet() {
        ErrorState.set("something")
        ErrorState.clear()
        #expect(ErrorState.get() == nil)
    }

    @Test("Overwriting: set twice, get returns latest")
    func overwrite() {
        ErrorState.set("first")
        ErrorState.set("second")
        #expect(ErrorState.get() == "second")
        ErrorState.clear()
    }

    @Test("Thread isolation: error set on thread A not visible on thread B")
    func threadIsolation() async {
        ErrorState.clear()
        ErrorState.set("main thread error")

        let otherThreadValue = await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                let val = ErrorState.get()
                continuation.resume(returning: val)
            }
        }
        #expect(otherThreadValue == nil)
        ErrorState.clear()
    }
}

@Suite("ErrorBuffer")
struct ErrorBufferTests {
    @Test("store(nil) returns nil")
    func storeNilReturnsNil() {
        let result = ErrorBuffer.store(nil)
        #expect(result == nil)
    }

    @Test("store(string) returns valid C string matching content")
    func storeStringReturnsValidCString() {
        let ptr = ErrorBuffer.store("hello")
        #expect(ptr != nil)
        #expect(String(cString: ptr!) == "hello")
    }

    @Test("Calling store again replaces previous buffer")
    func storeReplacesBuffer() {
        _ = ErrorBuffer.store("first")
        let ptr = ErrorBuffer.store("second")
        #expect(ptr != nil)
        #expect(String(cString: ptr!) == "second")
    }

    @Test("Thread isolation: buffers on different threads don't interfere")
    func threadIsolation() async {
        // Run everything on explicit threads to avoid Swift concurrency
        // hopping threads after an await (which would change the thread ID
        // used by ErrorBuffer).
        let results = await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                let mainPtr = ErrorBuffer.store("main")
                let mainBefore = mainPtr != nil ? String(cString: mainPtr!) : nil

                let sem = DispatchSemaphore(value: 0)
                nonisolated(unsafe) var otherValue: String?
                Thread.detachNewThread {
                    let ptr = ErrorBuffer.store("other")
                    otherValue = ptr != nil ? String(cString: ptr!) : nil
                    sem.signal()
                }
                sem.wait()

                let mainAfter = mainPtr != nil ? String(cString: mainPtr!) : nil
                continuation.resume(returning: (mainBefore, mainAfter, otherValue))
            }
        }
        #expect(results.0 == "main")
        #expect(results.1 == "main")
        #expect(results.2 == "other")
    }
}
