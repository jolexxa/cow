import Foundation
import MLX
import MLXLMCommon

/// Custom sampler conforming to MLXLMCommon's `LogitSampler` protocol.
///
/// Adds topK and minP filtering on top of temperature-scaled categorical
/// sampling. TopP and repetition penalty are handled by Apple's built-in
/// `TopPSampler` and `RepetitionContext` respectively, but topK and minP
/// are not provided out of the box — so we implement them here.
struct CustomSampler: LogitSampler {
    let temperature: Float
    let topK: Int
    let minP: Float
    let topP: Float

    /// Random state for reproducible sampling.
    let randomState: MLXRandom.RandomState

    init(temperature: Float, topP: Float, topK: Int, minP: Float, seed: Int) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.minP = minP
        if seed != 0 {
            self.randomState = MLXRandom.RandomState(seed: UInt64(seed))
        } else {
            self.randomState = MLXRandom.RandomState()
        }
    }

    func sample(logits rawLogits: MLXArray) -> MLXArray {
        var logits = rawLogits
        if logits.dtype == .bfloat16 {
            logits = logits.asType(.float32)
        }

        // Greedy.
        if temperature <= 0 {
            return argMax(logits, axis: -1)
        }

        // Top-K filtering.
        if topK > 0 {
            let vocabSize = logits.dim(-1)
            let k = min(topK, vocabSize)
            let sorted = MLX.sorted(logits, axis: -1)
            // Keep dims so threshold is [B, 1] for broadcast with [B, V].
            let threshold = sorted[0..., vocabSize - k].expandedDimensions(axis: -1)
            logits = MLX.where(logits .>= threshold, logits, MLXArray(Float(-1e9)))
        }

        // Min-P filtering.
        if minP > 0 {
            let probs = softmax(logits, axis: -1)
            // keepDims so maxProb is [B, 1] for broadcast with [B, V].
            let maxProb = probs.max(axis: -1, keepDims: true)
            let threshold = maxProb * minP
            logits = MLX.where(probs .>= threshold, logits, MLXArray(Float(-1e9)))
        }

        // Temperature + top-P + categorical.
        let scaled = logits / temperature

        return withRandomState(randomState) {
            if topP > 0 && topP < 1.0 {
                // Sample per-row to avoid advanced indexing issues with batch.
                let B = scaled.dim(0)
                var results = [MLXArray]()
                for i in 0 ..< B {
                    let row = scaled[i]  // [V]
                    let probs = softmax(row)
                    let sortedIndices = argSort(probs, axis: -1)
                    let sortedProbs = take(probs, sortedIndices, axis: -1)
                    let cumProbs = cumsum(sortedProbs, axis: -1)
                    let topProbs = MLX.where(
                        cumProbs .> (1 - topP), sortedProbs, zeros(like: sortedProbs))
                    let sortedToken = categorical(log(topProbs))
                    results.append(sortedIndices[sortedToken])
                }
                return stacked(results)
            } else {
                return categorical(scaled)
            }
        }
    }
}
