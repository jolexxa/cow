// ByteDecoder.swift — Token string → raw UTF-8 bytes.
//
// Based on swift-transformers (Apache 2.0 license):
// https://github.com/huggingface/swift-transformers
// See: Sources/Tokenizers/Decoder.swift
//   - ByteLevelDecoder (GPT-2 byte table)
//   - ByteFallbackDecoder (SentencePiece <0xHH> tokens)
//
// Two encoding schemes are common across HuggingFace models:
//
// 1. **ByteLevel (GPT-2)** — every byte (0–255) maps to a unique Unicode
//    character so that BPE operates on printable strings. Used by Qwen,
//    Llama 3+, DeepSeek, StableLM.
//
// 2. **ByteFallback (SentencePiece)** — raw bytes are encoded as `<0xHH>`
//    tokens, and the metaspace character `▁` (U+2581) represents a leading
//    space. Used by Llama 2, Mistral, Mixtral, Phi-3, Yi, Gemma 2.
//
// This file provides the inverse mapping for both: given a token string
// from the vocabulary, produce the original raw bytes so Dart can do its
// own UTF-8 reassembly.

import Foundation

/// Maps each byte-encoded character back to its original byte value.
/// Inverse of the GPT-2 `byteEncoder` table.
private let byteDecoder: [Character: UInt8] = {
    // Build the forward table (byte → character), then invert.
    var encoder = [UInt8: Character]()

    // Printable ASCII range (no remapping needed).
    for b: UInt8 in 33...126 { encoder[b] = Character(Unicode.Scalar(b)) }
    for b: UInt8 in 161...172 { encoder[b] = Character(Unicode.Scalar(b)) }
    for b: UInt8 in 174...255 { encoder[b] = Character(Unicode.Scalar(b)) }

    // Remaining bytes are remapped to U+0100 onwards.
    var codepoint: UInt32 = 0x0100
    for b: UInt8 in 0...255 {
        if encoder[b] == nil {
            encoder[b] = Character(Unicode.Scalar(codepoint)!)
            codepoint += 1
        }
    }

    // Invert: character → byte.
    var decoder = [Character: UInt8]()
    for (byte, char) in encoder {
        decoder[char] = byte
    }
    return decoder
}()

/// Converts a token string to raw UTF-8 bytes using the appropriate decoder.
func tokenStringToBytes(_ tokenString: String, decoderType: TokenDecoderType) -> [UInt8] {
    switch decoderType {
    case .byteLevel:    return tokenStringToBytesGPT2(tokenString)
    case .byteFallback: return tokenStringToBytesFallback(tokenString)
    }
}

// MARK: - ByteLevel (GPT-2)

/// Converts a GPT-2 byte-encoded token string to raw UTF-8 bytes.
///
/// Each character in the token string maps to exactly one byte via the
/// GPT-2 byte encoder table. The resulting bytes may form partial UTF-8
/// sequences — the caller is responsible for buffering and reassembly.
private func tokenStringToBytesGPT2(_ tokenString: String) -> [UInt8] {
    var bytes: [UInt8] = []
    for char in tokenString {
        if let b = byteDecoder[char] {
            bytes.append(b)
        } else {
            // Raw Unicode character (not in GPT-2 byte table) — encode as UTF-8.
            bytes.append(contentsOf: String(char).utf8)
        }
    }
    return bytes
}

// MARK: - ByteFallback (SentencePiece)

/// Converts a SentencePiece ByteFallback token string to raw UTF-8 bytes.
///
/// Based on swift-transformers `ByteFallbackDecoder.parseByte()`:
/// - `<0xHH>` tokens decode to the single byte `0xHH`.
/// - The metaspace `▁` (U+2581) is replaced with a regular space.
/// - Everything else is passed through as UTF-8.
private func tokenStringToBytesFallback(_ tokenString: String) -> [UInt8] {
    // <0xHH> → single byte
    if tokenString.count == 6,
       tokenString.hasPrefix("<0x"),
       tokenString.hasSuffix(">") {
        let hex = tokenString.dropFirst(3).dropLast()
        if let byte = UInt8(hex, radix: 16) {
            return [byte]
        }
    }

    // Replace metaspace ▁ (U+2581) with space, then encode as UTF-8.
    let cleaned = tokenString.replacingOccurrences(of: "\u{2581}", with: " ")
    return Array(cleaned.utf8)
}
