import Foundation
import MLXLMCommon

/// Mutable box wrapping the value-type `TokenIterator` so it can be
/// mutated through a reference held by `CowMLXContext`.
final class TokenIteratorBox: @unchecked Sendable {
    var iterator: TokenIterator

    init(_ iterator: TokenIterator) {
        self.iterator = iterator
    }
}

/// Generation context — owns the iterator, stop-token set, and KV cache
/// for a single generation session.
///
/// All contexts share the default GPU stream. MLX's internal `evalLock`
/// serializes eval calls, so separate streams provided no parallelism
/// and their global-default swap was a race condition source.
///
/// Ownership model:
/// - `model` is **shared** (read-only weights, safe across contexts).
/// - Everything else is **owned** by this context exclusively.
final class CowMLXContext: @unchecked Sendable {
    let model: CowMLXModel
    let maxTokens: Int32

    var iteratorBox: TokenIteratorBox?
    var stopTokenIds: Set<Int> = []

    /// Persistent KV cache across generation calls (one per layer).
    /// Created on first generateBegin, reused on subsequent incremental calls.
    var cache: [KVCache]?

    /// Token IDs that produced the current KV cache state.
    /// Used for native-side prefix comparison on incremental calls.
    var cachedTokens: [Int] = []

    init(model: CowMLXModel, maxTokens: Int32) {
        self.model = model
        self.maxTokens = maxTokens
    }

    func reset() {
        iteratorBox = nil
        stopTokenIds = []
        cache = nil
        cachedTokens = []
    }

    /// Trim n tokens from the END of the KV cache (undo).
    @discardableResult
    func trimCacheEnd(_ n: Int) -> Int {
        guard let cache else { return 0 }
        var actual = 0
        for c in cache {
            actual = c.trim(n)
        }
        return actual
    }

    /// Trim n tokens from the FRONT of the KV cache (sliding window eviction).
    /// Uses the state getter/setter on each layer's cache to slice the arrays.
    @discardableResult
    func trimCacheFront(_ n: Int) -> Int {
        guard var caches = cache else { return 0 }
        var actual = 0
        for i in caches.indices {
            var s = caches[i].state
            guard s.count == 2 else { continue }
            let layerActual = min(n, caches[i].offset)
            guard layerActual > 0 else { continue }
            // Axis 2 = sequence dimension. Drop first `layerActual` tokens.
            s[0] = s[0][.ellipsis, layerActual..., 0...]
            s[1] = s[1][.ellipsis, layerActual..., 0...]
            caches[i].state = s
            actual = layerActual
        }
        cache = caches
        return actual
    }
}
