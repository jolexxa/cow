import Foundation
import Testing

@testable import CowMLX

@Suite("HandleRegistry")
struct HandleRegistryTests {
    @Test("Insert returns incrementing handles")
    func insertReturnsIncrementingHandles() {
        let registry = HandleRegistry<NSObject>()
        let a = registry.insert(NSObject())
        let b = registry.insert(NSObject())
        let c = registry.insert(NSObject())
        #expect(a == 0)
        #expect(b == 1)
        #expect(c == 2)
    }

    @Test("Get returns inserted object")
    func getReturnsInsertedObject() {
        let registry = HandleRegistry<NSObject>()
        let obj = NSObject()
        let handle = registry.insert(obj)
        #expect(registry.get(handle) === obj)
    }

    @Test("Get returns nil for invalid handle")
    func getReturnsNilForInvalidHandle() {
        let registry = HandleRegistry<NSObject>()
        #expect(registry.get(999) == nil)
    }

    @Test("Remove returns object and subsequent get returns nil")
    func removeReturnsObjectThenGetReturnsNil() {
        let registry = HandleRegistry<NSObject>()
        let obj = NSObject()
        let handle = registry.insert(obj)
        let removed = registry.remove(handle)
        #expect(removed === obj)
        #expect(registry.get(handle) == nil)
    }

    @Test("Remove on invalid handle returns nil")
    func removeInvalidHandleReturnsNil() {
        let registry = HandleRegistry<NSObject>()
        #expect(registry.remove(999) == nil)
    }

    @Test("Thread safety: concurrent insert/get/remove")
    func threadSafety() {
        let registry = HandleRegistry<NSObject>()
        let iterations = 1000

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            let obj = NSObject()
            let handle = registry.insert(obj)
            #expect(registry.get(handle) === obj)
            let removed = registry.remove(handle)
            #expect(removed === obj)
            #expect(registry.get(handle) == nil)
        }
    }
}
