import Foundation
import Testing

@testable import CowMLX

@Suite("IdGenerator")
struct IdGeneratorTests {
    @Test("IDs monotonically increase")
    func idsMonotonicallyIncrease() {
        let gen = IdGenerator()
        let a = gen.next()
        let b = gen.next()
        let c = gen.next()
        #expect(a == 0)
        #expect(b == 1)
        #expect(c == 2)
    }

    @Test("Thread safety: concurrent generation produces unique IDs")
    func threadSafety() {
        let gen = IdGenerator()
        let iterations = 1000
        let lock = NSLock()
        nonisolated(unsafe) var ids: Set<Int64> = []

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            let id = gen.next()
            lock.lock()
            ids.insert(id)
            lock.unlock()
        }
        #expect(ids.count == iterations)
    }
}
