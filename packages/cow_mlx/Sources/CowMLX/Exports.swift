import Foundation
@preconcurrency import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

// MARK: - Global State

private let models = HandleRegistry<CowMLXModel>()
private let contexts = HandleRegistry<CowMLXContext>()

/// Maps model.id → handle for cross-isolate sharing.
nonisolated(unsafe) private var modelIdMap: [Int64: Int32] = [:]
private let modelIdMapLock = NSLock()

/// Serializes model loading. LLMModelFactory is NOT thread-safe
/// (weight loading happens outside MLX's evalLock).
private let modelLoadLock = NSLock()

// MARK: - Bridging Helpers

/// Bridge sync FFI → async Swift. Spawns a Task, blocks the caller with
/// a semaphore until it completes.
private func runBlocking<T>(_ body: @escaping @Sendable () async throws -> T) throws -> T {
    let box = ResultBox<T>()
    Task {
        do {
            let value = try await body()
            box.set(.success(value))
        } catch {
            box.set(.failure(error))
        }
    }
    box.wait()
    return try box.get()
}

/// Thread-safe box for passing a result from a Task back to the blocked caller.
private final class ResultBox<T>: @unchecked Sendable {
    private let sem = DispatchSemaphore(value: 0)
    private var result: Result<T, Error>?

    func set(_ value: Result<T, Error>) {
        result = value
        sem.signal()
    }

    func wait() {
        sem.wait()
    }

    func get() throws -> T {
        try result!.get()
    }
}

// MARK: - Error Reporting

@_cdecl("cow_mlx_get_error")
public func cow_mlx_get_error() -> UnsafePointer<CChar>? {
    return ErrorBuffer.store(ErrorState.get())
}

// MARK: - Lifecycle

@_cdecl("cow_mlx_init")
public func cow_mlx_init() -> Bool {
    // Cap the Metal buffer cache at 32 MB. MLX keeps freed intermediate
    // buffers in a pool for reuse, but as the KV cache grows each turn
    // the buffer sizes change so old ones can't be reused — they just
    // pile up. Without a limit this can grow to several GB.
    // 32 MB is generous enough for buffer reuse without runaway growth.
    Memory.cacheLimit = 32 * 1024 * 1024
    ErrorState.clear()
    return true
}

@_cdecl("cow_mlx_shutdown")
public func cow_mlx_shutdown() {
    // No global cleanup needed — models are freed individually.
}

// MARK: - Model Loading

@_cdecl("cow_mlx_load_model")
public func cow_mlx_load_model(
    _ modelPath: UnsafePointer<CChar>?,
    _ progressCb: (@convention(c) (Float, UnsafeMutableRawPointer?) -> Bool)?,
    _ userData: UnsafeMutableRawPointer?
) -> Int32 {
    guard let modelPath else {
        ErrorState.set("model_path is NULL")
        return -1
    }

    let path = String(cString: modelPath)
    let directoryURL = URL(fileURLWithPath: path)

    // Detect tokenizer byte decoding strategy from tokenizer.json.
    let decoderType = detectDecoderType(modelDirectory: directoryURL)

    // Wrap raw pointer for Sendable crossing.
    nonisolated(unsafe) let userDataSafe = userData

    do {
        // LLMModelFactory is not thread-safe — serialize loading.
        modelLoadLock.lock()
        defer { modelLoadLock.unlock() }

        let (container, config) = try runBlocking {
            let config = ModelConfiguration(directory: directoryURL)
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { progress in
                if let progressCb {
                    let shouldContinue = progressCb(
                        Float(progress.fractionCompleted), userDataSafe
                    )
                    if !shouldContinue {
                        // TODO: cancellation — for now we just keep going.
                    }
                }
            }
            return (container, config)
        }

        let model = CowMLXModel(
            container: container,
            configuration: config
        )
        model.decoderType = decoderType

        // Cache the tokenizer for synchronous access in tokenize/is_eog.
        model.cachedTokenizer = try runBlocking {
            await container.tokenizer
        }

        let handle = models.insert(model)

        modelIdMapLock.lock()
        modelIdMap[model.id] = handle
        modelIdMapLock.unlock()

        ErrorState.clear()
        return handle
    } catch {
        ErrorState.set("Failed to load model: \(error)")
        return -1
    }
}

@_cdecl("cow_mlx_free_model")
public func cow_mlx_free_model(_ model: Int32) {
    guard let m = models.remove(model) else { return }
    modelIdMapLock.lock()
    modelIdMap.removeValue(forKey: m.id)
    modelIdMapLock.unlock()
}

@_cdecl("cow_mlx_model_get_id")
public func cow_mlx_model_get_id(_ model: Int32) -> Int64 {
    guard let m = models.get(model) else { return -1 }
    return m.id
}

@_cdecl("cow_mlx_model_from_id")
public func cow_mlx_model_from_id(_ modelId: Int64) -> Int32 {
    modelIdMapLock.lock()
    defer { modelIdMapLock.unlock() }
    return modelIdMap[modelId] ?? -1
}

// MARK: - Context

@_cdecl("cow_mlx_create_context")
public func cow_mlx_create_context(_ model: Int32, _ maxTokens: Int32) -> Int32 {
    guard let m = models.get(model) else {
        ErrorState.set("Invalid model handle")
        return -1
    }
    let ctx = CowMLXContext(model: m, maxTokens: maxTokens)
    ErrorState.clear()
    return contexts.insert(ctx)
}

@_cdecl("cow_mlx_free_context")
public func cow_mlx_free_context(_ context: Int32) {
    contexts.remove(context)
}

@_cdecl("cow_mlx_reset_context")
public func cow_mlx_reset_context(_ context: Int32) -> Bool {
    guard let ctx = contexts.get(context) else {
        ErrorState.set("Invalid context handle")
        return false
    }
    ctx.reset()
    ErrorState.clear()
    return true
}

// MARK: - Tokenization

@_cdecl("cow_mlx_tokenize")
public func cow_mlx_tokenize(
    _ model: Int32,
    _ text: UnsafePointer<CChar>?,
    _ textLen: Int32,
    _ outTokens: UnsafeMutablePointer<Int32>?,
    _ maxTokens: Int32,
    _ addSpecial: Bool
) -> Int32 {
    guard let m = models.get(model) else {
        ErrorState.set("Invalid model handle")
        return -1
    }
    guard let text else {
        ErrorState.set("text is NULL")
        return -1
    }
    guard let tokenizer = m.cachedTokenizer else {
        ErrorState.set("Tokenizer not cached — model not fully loaded")
        return -1
    }

    let str = String(cString: text)
    let tokens = tokenizer.encode(text: str, addSpecialTokens: addSpecial)
    let count = Int32(tokens.count)

    // If outTokens is NULL, just return the count.
    guard let outTokens else {
        return count
    }

    if count > maxTokens {
        // Buffer too small — return negative required size.
        return -count
    }

    for (i, tok) in tokens.enumerated() {
        outTokens[i] = Int32(tok)
    }

    ErrorState.clear()
    return count
}

@_cdecl("cow_mlx_is_eog")
public func cow_mlx_is_eog(_ model: Int32, _ token: Int32) -> Bool {
    guard let m = models.get(model) else { return false }
    guard let tokenizer = m.cachedTokenizer else { return false }

    if let eosId = tokenizer.eosTokenId, eosId == Int(token) {
        return true
    }
    if m.configuration.eosTokenIds.contains(Int(token)) {
        return true
    }
    return false
}

// MARK: - Generation

@_cdecl("cow_mlx_generate_begin")
public func cow_mlx_generate_begin(
    _ context: Int32,
    _ tokens: UnsafePointer<Int32>?,
    _ tokenCount: Int32,
    _ temperature: Float,
    _ topP: Float,
    _ topK: Int32,
    _ minP: Float,
    _ repeatPenalty: Float,
    _ repeatWindow: Int32,
    _ seed: Int32
) -> Bool {
    guard let ctx = contexts.get(context) else {
        ErrorState.set("Invalid context handle")
        return false
    }
    guard let tokens, tokenCount > 0 else {
        ErrorState.set("tokens is NULL or empty")
        return false
    }

    let tokenArray = (0..<Int(tokenCount)).map { Int(tokens[$0]) }

    do {
        try runBlocking {
            try await ctx.model.container.perform { modelContext in
                let prefixLen = zip(tokenArray, ctx.cachedTokens)
                    .prefix(while: ==).count

                let cache: [KVCache]
                if prefixLen > 0, let existing = ctx.cache {
                    let tokensToTrim = ctx.cachedTokens.count - prefixLen
                    if tokensToTrim > 0 {
                        for c in existing { c.trim(tokensToTrim) }
                    }
                    cache = existing
                } else {
                    cache = modelContext.model.newCache(parameters: nil)
                }

                let newTokens: [Int]
                if prefixLen < tokenArray.count {
                    newTokens = Array(tokenArray[prefixLen...])
                } else {
                    newTokens = [tokenArray.last!]
                }
                let inputTokens = MLXArray(newTokens)
                let input = LMInput(tokens: inputTokens)

                let sampler = CustomSampler(
                    temperature: temperature,
                    topP: topP,
                    topK: Int(topK),
                    minP: minP,
                    seed: Int(seed)
                )

                var processor: LogitProcessor? = nil
                if repeatPenalty > 1.0 && repeatWindow > 0 {
                    processor = RepetitionContext(
                        repetitionPenalty: repeatPenalty,
                        repetitionContextSize: Int(repeatWindow)
                    )
                }

                let iterator = try TokenIterator(
                    input: input,
                    model: modelContext.model,
                    cache: cache,
                    processor: processor,
                    sampler: sampler,
                    // Empirical testing for prefill step size on common
                    // macOS hardware is available here:
                    // https://github.com/thornad/lmstudio-mlx-patch
                    // https://github.com/lmstudio-ai/lmstudio-js/issues/507
                    //
                    // A higher number helps reduce warmup time to first token
                    // at the expense of memory usage.
                    prefillStepSize: 4096
                )

                ctx.iteratorBox = TokenIteratorBox(iterator)
                ctx.cache = cache
                ctx.cachedTokens = tokenArray

                var stopIds = modelContext.configuration.eosTokenIds
                if let eosId = modelContext.tokenizer.eosTokenId {
                    stopIds.insert(eosId)
                }
                for token in modelContext.configuration.extraEOSTokens {
                    if let id = modelContext.tokenizer.convertTokenToId(token) {
                        stopIds.insert(id)
                    }
                }
                ctx.stopTokenIds = stopIds
            }
        }

        ErrorState.clear()
        return true
    } catch {
        ErrorState.set("generate_begin failed: \(error)")
        return false
    }
}

@_cdecl("cow_mlx_generate_next")
public func cow_mlx_generate_next(
    _ context: Int32,
    _ buf: UnsafeMutablePointer<CChar>?,
    _ bufLen: Int32
) -> Int32 {
    guard let ctx = contexts.get(context) else {
        ErrorState.set("Invalid context handle")
        return -1
    }
    guard let box = ctx.iteratorBox else {
        ErrorState.set("No active generation — call generate_begin first")
        return -1
    }

    // Wrap raw pointer for Sendable crossing.
    nonisolated(unsafe) let bufSafe = buf

    do {
        return try runBlocking {
            guard let token = box.iterator.next() else {
                ErrorState.clear()
                return Int32(-1)
            }

            if ctx.stopTokenIds.contains(token) {
                ErrorState.clear()
                return Int32(-1)
            }

            // Get the raw token string from the vocabulary and convert
            // to raw bytes via the GPT-2 byte decoder table. Dart will
            // handle UTF-8 reassembly via its chunked Utf8Decoder.
            guard let tokenizer = ctx.model.cachedTokenizer,
                  let tokenString = tokenizer.convertIdToToken(token) else {
                ErrorState.clear()
                return Int32(0)
            }

            let bytes = tokenStringToBytes(tokenString, decoderType: ctx.model.decoderType)
            let count = Int32(bytes.count)

            guard count > 0 else {
                ErrorState.clear()
                return Int32(0)
            }

            guard let bufSafe else {
                return count
            }

            if count > bufLen {
                return -count
            }

            for i in 0..<Int(count) {
                bufSafe[i] = CChar(bitPattern: bytes[i])
            }

            ErrorState.clear()
            return count
        }
    } catch {
        ErrorState.set("generate_next failed: \(error)")
        return -1
    }
}

// MARK: - KV Cache Management

@_cdecl("cow_mlx_cache_token_count")
public func cow_mlx_cache_token_count(_ context: Int32) -> Int32 {
    guard let ctx = contexts.get(context) else {
        ErrorState.set("Invalid context handle")
        return -1
    }
    return Int32(ctx.cache?.first?.offset ?? 0)
}

@_cdecl("cow_mlx_cache_trim_end")
public func cow_mlx_cache_trim_end(_ context: Int32, _ n: Int32) -> Int32 {
    guard let ctx = contexts.get(context) else {
        ErrorState.set("Invalid context handle")
        return -1
    }
    return Int32(ctx.trimCacheEnd(Int(n)))
}

@_cdecl("cow_mlx_cache_trim_front")
public func cow_mlx_cache_trim_front(_ context: Int32, _ n: Int32) -> Int32 {
    guard let ctx = contexts.get(context) else {
        ErrorState.set("Invalid context handle")
        return -1
    }
    return Int32(ctx.trimCacheFront(Int(n)))
}
