// TokenizerDetector.swift — Auto-detect byte decoding strategy from tokenizer.json.
//
// Based on swift-transformers (Apache 2.0 license):
// https://github.com/huggingface/swift-transformers
// See: Sources/Tokenizers/Decoder.swift (DecoderFactory, DecoderType enum)
//
// HuggingFace model directories include a `tokenizer.json` with a `decoder`
// field that identifies how vocabulary strings map to raw bytes. We read this
// at model load time so we can dispatch to the correct byte decoder.

import Foundation

/// Inspects `tokenizer.json` in the model directory and returns the
/// appropriate ``TokenDecoderType``.
///
/// Detection logic (mirrors swift-transformers `DecoderFactory`):
/// - `decoder.type == "ByteLevel"` → `.byteLevel`
/// - `decoder.type == "Sequence"` with a `"ByteFallback"` step → `.byteFallback`
/// - Missing file / unknown type → `.byteLevel` (safe default)
func detectDecoderType(modelDirectory: URL) -> TokenDecoderType {
    let tokenizerURL = modelDirectory.appendingPathComponent("tokenizer.json")

    guard let data = try? Data(contentsOf: tokenizerURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let decoder = json["decoder"] as? [String: Any],
          let type = decoder["type"] as? String else {
        return .byteLevel
    }

    switch type {
    case "ByteLevel":
        return .byteLevel

    case "Sequence":
        // Check if any step in the sequence is a ByteFallback decoder.
        if let decoders = decoder["decoders"] as? [[String: Any]] {
            for step in decoders {
                if let stepType = step["type"] as? String,
                   stepType == "ByteFallback" {
                    return .byteFallback
                }
            }
        }
        return .byteLevel

    case "ByteFallback":
        // Standalone ByteFallback (unusual but possible).
        return .byteFallback

    default:
        return .byteLevel
    }
}
