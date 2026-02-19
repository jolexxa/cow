import Foundation
@preconcurrency import MLX
import MLXLMCommon
import MLXLLM
import Tokenizers

// MARK: - Global State

private let models = HandleRegistry<CowMLXModel>()
private let contexts = HandleRegistry<CowMLXContext>()

/// Maps model.id → handle for cross-isolate sharing.
nonisolated(unsafe) private var modelIdMap: [Int64: Int32] = [:]
private let modelIdMapLock = NSLock()

/// Dedicated queue for bridging Swift async → synchronous C calls.
/// This MUST be different from the Swift cooperative thread pool to avoid
/// deadlocks when blocking with a semaphore.
private let mlxQueue = DispatchQueue(label: "com.cow.mlx", qos: .userInitiated)

// MARK: - Async Bridging

/// Run an async closure synchronously by dispatching to mlxQueue and blocking
/// the calling thread with a semaphore.
private func runBlocking<T>(_ body: @escaping @Sendable () async throws -> T) throws -> T {
    let sem = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Result<T, Error>?

    mlxQueue.async {
        Task {
            do {
                let value = try await body()
                result = .success(value)
            } catch {
                result = .failure(error)
            }
            sem.signal()
        }
    }

    sem.wait()
    return try result!.get()
}

// MARK: - Error Reporting

@_cdecl("cow_mlx_get_error")
public func cow_mlx_get_error() -> UnsafePointer<CChar>? {
    return ErrorBuffer.store(ErrorState.get())
}

// MARK: - Lifecycle

@_cdecl("cow_mlx_init")
public func cow_mlx_init() -> Bool {
    // MLX manages GPU memory internally.
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

    // Wrap raw pointer for Sendable crossing.
    nonisolated(unsafe) let userDataSafe = userData

    do {
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

    let str = String(cString: text)

    do {
        let tokens: [Int] = try runBlocking {
            let tokenizer = await m.container.tokenizer
            return tokenizer.encode(text: str, addSpecialTokens: addSpecial)
        }

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
    } catch {
        ErrorState.set("Tokenization failed: \(error)")
        return -1
    }
}

@_cdecl("cow_mlx_is_eog")
public func cow_mlx_is_eog(_ model: Int32, _ token: Int32) -> Bool {
    guard let m = models.get(model) else { return false }

    do {
        return try runBlocking {
            let tokenizer = await m.container.tokenizer
            // Check against EOS token ID.
            if let eosId = tokenizer.eosTokenId, eosId == Int(token) {
                return true
            }
            // Check against extra EOS tokens from configuration.
            if m.configuration.eosTokenIds.contains(Int(token)) {
                return true
            }
            return false
        }
    } catch {
        return false
    }
}

// MARK: - Generation

/// Begin a generation session. Tokenizes the prompt, creates the
/// `TokenIterator` (which does prefill internally), and stores the
/// iterator + detokenizer on the context.
///
/// Sampling parameters are passed as individual C arguments to avoid
/// a struct parameter (simpler FFI).
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
                // Build the LMInput from token IDs.
                let inputTokens = MLXArray(tokenArray)
                let input = LMInput(tokens: inputTokens)

                // Create our custom sampler (topK + minP + topP + temperature).
                let sampler = CustomSampler(
                    temperature: temperature,
                    topP: topP,
                    topK: Int(topK),
                    minP: minP,
                    seed: Int(seed)
                )

                // Use Apple's RepetitionContext for repeat penalty if enabled.
                var processor: LogitProcessor? = nil
                if repeatPenalty > 1.0 && repeatWindow > 0 {
                    processor = RepetitionContext(
                        repetitionPenalty: repeatPenalty,
                        repetitionContextSize: Int(repeatWindow)
                    )
                }

                // Create the TokenIterator — this does prefill + first sample
                // internally, using asyncEval for GPU pipelining.
                let maxKVSize = ctx.maxTokens > 0 ? Int(ctx.maxTokens) : nil
                let cache = modelContext.model.newCache(
                    parameters: GenerateParameters(maxKVSize: maxKVSize)
                )

                let iterator = try TokenIterator(
                    input: input,
                    model: modelContext.model,
                    cache: cache,
                    processor: processor,
                    sampler: sampler,
                    prefillStepSize: 512
                )

                ctx.iteratorBox = TokenIteratorBox(iterator)

                // Build the stop-token set.
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

                // Create the streaming detokenizer.
                ctx.detokenizer = NaiveStreamingDetokenizer(
                    tokenizer: modelContext.tokenizer
                )
            }
        }

        ErrorState.clear()
        return true
    } catch {
        ErrorState.set("generate_begin failed: \(error)")
        return false
    }
}

/// Advance generation by one token. Returns the new text (if any)
/// produced by the streaming detokenizer.
///
/// - Returns: Number of UTF-8 bytes written to `buf`.
///   - `> 0`: text available.
///   - `0`: token produced an incomplete character (e.g. partial emoji).
///   - `-1`: generation is done (EOG or iterator exhausted).
///   - `< -1`: buffer too small (absolute value = required size).
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

    // TokenIterator.next() is synchronous — no runBlocking needed.
    // Model weights are read-only after prefill; KV cache is owned
    // by the iterator.
    guard let token = box.iterator.next() else {
        // Iterator exhausted (max tokens reached).
        ErrorState.clear()
        return -1
    }

    // Check for end-of-generation tokens.
    if ctx.stopTokenIds.contains(token) {
        ErrorState.clear()
        return -1
    }

    // Feed token into the streaming detokenizer.
    ctx.detokenizer?.append(token: token)
    guard let text = ctx.detokenizer?.next(), !text.isEmpty else {
        // Incomplete character — return 0 bytes.
        ErrorState.clear()
        return 0
    }

    let utf8 = Array(text.utf8)
    let count = Int32(utf8.count)

    guard let buf else {
        return count
    }

    if count > bufLen {
        return -count
    }

    utf8.withUnsafeBufferPointer { src in
        for i in 0..<Int(count) {
            buf[i] = CChar(bitPattern: src[i])
        }
    }

    ErrorState.clear()
    return count
}
