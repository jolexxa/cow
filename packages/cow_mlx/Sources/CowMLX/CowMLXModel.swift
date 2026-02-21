import Foundation
import MLXLMCommon
import Tokenizers

/// How the tokenizer maps vocabulary strings to raw bytes.
///
/// Based on swift-transformers (Apache 2.0 license):
/// https://github.com/huggingface/swift-transformers
/// See: Sources/Tokenizers/Decoder.swift (DecoderType enum)
enum TokenDecoderType: Sendable {
    /// GPT-2 ByteLevel — every byte maps to a unique Unicode character.
    /// Used by Qwen, Llama 3+, DeepSeek, StableLM.
    case byteLevel

    /// SentencePiece ByteFallback — raw bytes encoded as `<0xHH>` tokens,
    /// metaspace `▁` (U+2581) represents a leading space.
    /// Used by Llama 2, Mistral, Mixtral, Phi-3, Yi, Gemma 2.
    case byteFallback
}

/// Thread-safe monotonically increasing ID generator.
final class IdGenerator: @unchecked Sendable {
    private var nextId: Int64 = 0
    private let lock = NSLock()

    func next() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let id = nextId
        nextId += 1
        return id
    }
}

/// Wraps a loaded MLX model + tokenizer behind a handle.
final class CowMLXModel: @unchecked Sendable {
    let container: ModelContainer
    let configuration: ModelConfiguration
    let id: Int64

    /// Cached tokenizer for synchronous access. Resolved once after model
    /// loading so that `tokenize` and `is_eog` can be pure sync FFI calls
    /// without bridging through Task + semaphore.
    var cachedTokenizer: (any Tokenizer)?

    /// Detected at model load from `tokenizer.json`. Defaults to `.byteLevel`.
    var decoderType: TokenDecoderType = .byteLevel

    private static let idGen = IdGenerator()

    init(container: ModelContainer, configuration: ModelConfiguration) {
        self.container = container
        self.configuration = configuration
        self.id = CowMLXModel.idGen.next()
    }
}
