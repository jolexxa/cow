import Foundation
@preconcurrency import MLX
@preconcurrency import MLXLMCommon
import Tokenizers

/// Sequence entry in a batch — tracks per-sequence state.
struct BatchSequence {
    let id: Int32
    var tokens: [Int]
    var lastToken: MLXArray  // shape [1] — the most recently sampled token
}

/// Batch generation context — manages multiple sequences in a single
/// batched forward pass through the model.
///
/// Lifecycle:
///   1. Create with `init(model:maxTokens:)`
///   2. Add sequences with `addSequence(id:tokens:)`
///   3. Call `prefill(...)` to left-pad, create batch caches, and run prefill
///   4. Call `step()` repeatedly — returns per-sequence token bytes
///   5. Call `removeSequence(id:)` as sequences complete
///   6. Optionally call `addAndPrefillSequence(id:tokens:)` to extend the batch
final class CowMLXBatchContext: @unchecked Sendable {
    let model: CowMLXModel
    let maxTokens: Int32

    /// Per-layer batch KV caches (BatchKVCache or BatchRotatingKVCache).
    var cache: [KVCache]?

    /// Active sequences in the batch, in order.
    var sequences: [BatchSequence] = []

    /// Pending sequences queued for the next prefill.
    var pendingSequences: [(id: Int32, tokens: [Int])] = []

    /// Sampler instance (shared across all sequences).
    var sampler: CustomSampler?

    /// Stop token IDs for this model.
    var stopTokenIds: Set<Int> = []

    /// Prefill step size (tokens per prefill chunk).
    var prefillStepSize: Int = 4096

    init(model: CowMLXModel, maxTokens: Int32) {
        self.model = model
        self.maxTokens = maxTokens
    }

    /// Queue a sequence for the next prefill.
    func addSequence(id: Int32, tokens: [Int]) {
        pendingSequences.append((id: id, tokens: tokens))
    }

    /// Number of actively generating sequences.
    var activeCount: Int { sequences.count }

    /// Prefill all pending sequences. Creates batch caches, runs the model
    /// forward pass in chunks, and samples the first token per sequence.
    func prefill(
        model: any LanguageModel,
        tokenizer: Tokenizer,
        sampler: CustomSampler,
        stopTokenIds: Set<Int>
    ) {
        guard !pendingSequences.isEmpty else { return }

        self.sampler = sampler
        self.stopTokenIds = stopTokenIds

        let prompts = pendingSequences.map(\.tokens)
        let ids = pendingSequences.map(\.id)
        pendingSequences.removeAll()

        // Left-pad prompts to uniform length.
        let maxLen = prompts.map(\.count).max()!
        let leftPadding = prompts.map { maxLen - $0.count }

        var padded = [[Int]]()
        for (i, prompt) in prompts.enumerated() {
            let pad = Array(repeating: 0, count: leftPadding[i])
            padded.append(pad + prompt)
        }
        let paddedArray = MLXArray(padded.flatMap { $0 }, [prompts.count, maxLen])

        // Create batch caches.
        var batchCache = makeBatchCache(
            model: model,
            leftPadding: leftPadding
        )

        // Chunked prefill — process all but the last token.
        var remaining = paddedArray
        while remaining.dim(1) > 1 {
            let nToProcess = min(prefillStepSize, remaining.dim(1) - 1)
            let slice = remaining[0..., ..<nToProcess]
            _ = model(slice, cache: batchCache)
            let states = batchCache.flatMap(\.state)
            if !states.isEmpty {
                eval(states)
            }
            let length = remaining.dim(1)
            remaining = remaining[0..., nToProcess ..< length]
            GPU.clearCache()
        }

        // Final step — last token through model + sample.
        let logits = model(remaining, cache: batchCache)
        let selected = logits[0..., -1, 0...]  // [B, V]
        let sampled = sampler.sample(logits: selected)  // [B]
        asyncEval(sampled)

        // If we already have an active batch, extend it.
        if cache != nil && !sequences.isEmpty {
            // Extend existing batch with the new sequences.
            extendBatch(
                newCache: batchCache,
                newIds: ids,
                newTokens: prompts,
                newSampled: sampled
            )
        } else {
            // First batch — just store directly.
            cache = batchCache
            for (i, id) in ids.enumerated() {
                sequences.append(BatchSequence(
                    id: id,
                    tokens: prompts[i],
                    lastToken: sampled[i]
                ))
            }
        }
    }

    /// One decode step — runs model forward for all active sequences,
    /// samples one token per sequence, returns raw bytes per sequence.
    ///
    /// Must be called from within `container.perform { ... }` to access
    /// the model. The `languageModel` parameter is the model from the context.
    ///
    /// Returns array of (seqId, tokenId, tokenBytes). Empty array means no active sequences.
    func step(languageModel: any LanguageModel) -> [(id: Int32, tokenId: Int, bytes: [UInt8])] {
        guard !sequences.isEmpty, let cache = cache, let sampler = sampler else {
            return []
        }

        // Build batched input [B, 1] from each sequence's last token.
        let batchedTokens = MLXArray(
            sequences.map { $0.lastToken.item(Int32.self) },
            [sequences.count, 1]
        )

        // Model forward pass.
        let logits = batchModelForward(languageModel, batchedTokens, cache: cache)
        let selected = logits[0..., -1, 0...]  // [B, V]
        let sampled = sampler.sample(logits: selected)  // [B]
        asyncEval(sampled)

        // Build results and update state.
        var results: [(id: Int32, tokenId: Int, bytes: [UInt8])] = []

        guard let tokenizer = model.cachedTokenizer else {
            return results
        }

        for i in sequences.indices {
            let tokenId = sampled[i].item(Int.self)
            sequences[i].lastToken = sampled[i]
            sequences[i].tokens.append(tokenId)

            // Convert token to bytes.
            if let tokenString = tokenizer.convertIdToToken(tokenId) {
                let bytes = tokenStringToBytes(
                    tokenString, decoderType: model.decoderType)
                results.append((id: sequences[i].id, tokenId: tokenId, bytes: bytes))
            } else {
                results.append((id: sequences[i].id, tokenId: tokenId, bytes: []))
            }
        }

        return results
    }

    /// Remove a sequence from the batch by ID.
    /// Filters the batch caches to remove that sequence's entries.
    func removeSequence(id: Int32) -> Bool {
        guard let idx = sequences.firstIndex(where: { $0.id == id }) else {
            return false
        }

        sequences.remove(at: idx)

        if sequences.isEmpty {
            cache = nil
            return true
        }

        // Filter caches to keep remaining indices.
        let keepIndices = MLXArray(
            (0 ..< sequences.count + 1)
                .filter { $0 != idx }
                .map { Int32($0) }
        )

        guard let cache = cache else { return true }
        for i in cache.indices {
            switch cache[i] {
            case let batch as BatchKVCache:
                batch.filter(batchIndices: keepIndices)
            case let rotating as BatchRotatingKVCache:
                rotating.filter(batchIndices: keepIndices)
            case let arrays as ArraysCache:
                arrays.filter(batchIndices: keepIndices)
            case let list as CacheList:
                list.filter(batchIndices: keepIndices)
            default:
                break
            }
        }

        return true
    }

    /// Check if a token is an end-of-generation token.
    func isEOG(_ tokenId: Int) -> Bool {
        stopTokenIds.contains(tokenId)
    }

    // MARK: - Private

    private func extendBatch(
        newCache: [KVCache],
        newIds: [Int32],
        newTokens: [[Int]],
        newSampled: MLXArray
    ) {
        guard let existingCache = cache else { return }

        for i in existingCache.indices {
            switch (existingCache[i], newCache[i]) {
            case (let lhs as BatchKVCache, let rhs as BatchKVCache):
                lhs.extend(other: rhs)
            case (let lhs as BatchRotatingKVCache, let rhs as BatchRotatingKVCache):
                lhs.extend(other: rhs)
            case (let lhs as ArraysCache, let rhs as ArraysCache):
                lhs.extend(other: rhs)
            case (let lhs as CacheList, let rhs as CacheList):
                lhs.extend(other: rhs)
            default:
                break
            }
        }

        for (i, id) in newIds.enumerated() {
            sequences.append(BatchSequence(
                id: id,
                tokens: newTokens[i],
                lastToken: newSampled[i]
            ))
        }
    }
}

// MARK: - Model call helper

/// Call the model forward pass directly on the container's actor.
/// Must be called from within `container.perform { ... }`.
func batchModelForward(
    _ model: any LanguageModel, _ tokens: MLXArray, cache: [KVCache]
) -> MLXArray {
    model(tokens, cache: cache)
}
