import Foundation
import MLX
import Testing

@testable import CowMLX

/// MLX requires Metal + its compiled .metallib shader bundle.
/// `swift test` from the CLI doesn't bundle the metallib, so we gate these
/// tests behind an environment variable that can be set when running from
/// Xcode or a CI environment with Metal support.
///
/// Run with: `MLX_TESTS=1 swift test` (only works where Metal shaders are
/// available, e.g. Xcode test runner).
private let mlxTestsEnabled: Bool = {
    ProcessInfo.processInfo.environment["MLX_TESTS"] == "1"
}()

@Suite("CustomSampler", .enabled(if: mlxTestsEnabled, "Set MLX_TESTS=1 to enable"))
struct CustomSamplerTests {
    @Test("Greedy (temp=0) returns argmax")
    func greedy() {
        let sampler = CustomSampler(
            temperature: 0, topP: 1.0, topK: 0, minP: 0, seed: 42)
        let logits = MLXArray([1.0, 5.0, 3.0, 2.0] as [Float]).reshaped([1, 4])
        let result = sampler.sample(logits: logits)
        #expect(result.item(Int.self) == 1)
    }

    @Test("bfloat16 upcast: bfloat16 logits produce same result as float32")
    func bfloat16Upcast() {
        let sampler = CustomSampler(
            temperature: 0, topP: 1.0, topK: 0, minP: 0, seed: 42)
        let f32Logits = MLXArray([1.0, 5.0, 3.0, 2.0] as [Float]).reshaped([1, 4])
        let bf16Logits = f32Logits.asType(.bfloat16)
        let f32Result = sampler.sample(logits: f32Logits)
        let bf16Result = sampler.sample(logits: bf16Logits)
        #expect(f32Result.item(Int.self) == bf16Result.item(Int.self))
    }

    @Test("Top-K: K=2 on 5-vocab only samples from top 2 tokens")
    func topK() {
        // logits: [1, 5, 3, 2, 4] — top 2 are indices 1 (5.0) and 4 (4.0).
        // With temp > 0 and K=2, only those two should ever be sampled.
        let sampler = CustomSampler(
            temperature: 1.0, topP: 1.0, topK: 2, minP: 0, seed: 42)
        let logits = MLXArray([1.0, 5.0, 3.0, 2.0, 4.0] as [Float]).reshaped([1, 5])

        var seen = Set<Int>()
        for _ in 0..<100 {
            seen.insert(sampler.sample(logits: logits).item(Int.self))
        }
        // Should only ever produce index 1 or 4.
        #expect(seen.isSubset(of: [1, 4]))
        // Should see at least both (extremely unlikely to miss one in 100 draws).
        #expect(seen.count == 2)
    }

    @Test("Min-P: tokens below threshold never sampled")
    func minP() {
        // logits: [4.0, 5.0, 4.5, 0.0]
        // softmax ≈ [0.17, 0.47, 0.28, 0.03]
        // minP=0.3 → threshold = 0.47 * 0.3 = 0.14
        // Indices 0 (0.17), 1 (0.47), 2 (0.28) survive; index 3 (0.03) masked.
        let sampler = CustomSampler(
            temperature: 1.0, topP: 1.0, topK: 0, minP: 0.3, seed: 42)
        let logits = MLXArray([4.0, 5.0, 4.5, 0.0] as [Float]).reshaped([1, 4])

        var seen = Set<Int>()
        for _ in 0..<200 {
            seen.insert(sampler.sample(logits: logits).item(Int.self))
        }
        // Index 3 should never appear.
        #expect(!seen.contains(3))
        // Should see at least 2 of the surviving tokens.
        #expect(seen.count >= 2)
    }

    @Test("Top-P (nucleus): low-probability tail excluded")
    func topP() {
        // logits: [3.0, 5.0, 4.0, 0.5]
        // softmax ≈ [0.10, 0.74, 0.27, 0.008] (approx, before temp scaling)
        // With topP=0.85 and temp=1.0, the nucleus should cover the top tokens
        // (indices 1 + 2 ≈ 0.87) and exclude the tail.
        // Index 3 (prob ≈ 0.008) should almost never appear.
        let sampler = CustomSampler(
            temperature: 1.0, topP: 0.85, topK: 0, minP: 0, seed: 42)
        let logits = MLXArray([3.0, 5.0, 4.0, 0.5] as [Float]).reshaped([1, 4])

        var seen = Set<Int>()
        for _ in 0..<200 {
            seen.insert(sampler.sample(logits: logits).item(Int.self))
        }
        // Index 3 should be excluded by the nucleus cutoff.
        #expect(!seen.contains(3))
    }

    @Test("Temperature: higher temp produces more uniform distribution")
    func temperatureEffect() {
        let lowTempSampler = CustomSampler(
            temperature: 0.1, topP: 1.0, topK: 0, minP: 0, seed: 123)
        let highTempSampler = CustomSampler(
            temperature: 2.0, topP: 1.0, topK: 0, minP: 0, seed: 123)

        let logits = MLXArray([1.0, 2.0, 3.0, 4.0] as [Float]).reshaped([1, 4])

        var lowTempCounts = [Int: Int]()
        var highTempCounts = [Int: Int]()
        let runs = 200

        for _ in 0..<runs {
            let lowResult = lowTempSampler.sample(logits: logits).item(Int.self)
            lowTempCounts[lowResult, default: 0] += 1
            let highResult = highTempSampler.sample(logits: logits).item(Int.self)
            highTempCounts[highResult, default: 0] += 1
        }

        let lowMaxCount = lowTempCounts.values.max() ?? 0
        let highMaxCount = highTempCounts.values.max() ?? 0
        #expect(lowMaxCount > highMaxCount)
    }

    @Test("Seed determinism: same seed + logits produces same token")
    func seedDeterminism() {
        let logits = MLXArray([1.0, 2.0, 3.0, 1.5] as [Float]).reshaped([1, 4])

        let sampler1 = CustomSampler(
            temperature: 0.8, topP: 1.0, topK: 0, minP: 0, seed: 999)
        let result1 = sampler1.sample(logits: logits).item(Int.self)

        let sampler2 = CustomSampler(
            temperature: 0.8, topP: 1.0, topK: 0, minP: 0, seed: 999)
        let result2 = sampler2.sample(logits: logits).item(Int.self)

        #expect(result1 == result2)
    }
}
