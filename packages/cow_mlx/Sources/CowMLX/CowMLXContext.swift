import Foundation
import MLX
import MLXLMCommon

/// Mutable box wrapping the value-type `TokenIterator` so it can be
/// mutated through a reference held by `CowMLXContext`.
final class TokenIteratorBox: @unchecked Sendable {
    var iterator: TokenIterator

    init(_ iterator: TokenIterator) {
        self.iterator = iterator
    }
}

/// Generation context — owns the iterator, detokenizer, and stop-token set
/// for a single generation session.
final class CowMLXContext: @unchecked Sendable {
    let model: CowMLXModel
    let maxTokens: Int32
    var iteratorBox: TokenIteratorBox?
    var detokenizer: NaiveStreamingDetokenizer?
    var stopTokenIds: Set<Int> = []

    init(model: CowMLXModel, maxTokens: Int32) {
        self.model = model
        self.maxTokens = maxTokens
    }

    func reset() {
        iteratorBox = nil
        detokenizer = nil
        stopTokenIds = []
    }
}
