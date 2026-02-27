// Shared token-to-chunk decoding pipeline for generate loops.
// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:cow_brain/src/adapters/chunked_utf8.dart';
import 'package:cow_brain/src/adapters/stream_assembler.dart';
import 'package:cow_brain/src/adapters/stream_chunk.dart';

/// Decodes raw token bytes into [StreamChunk]s via chunked UTF-8 decoding
/// and stop-sequence detection.
///
/// Used by both llama.cpp and MLX runtimes to avoid duplicating the
/// UTF-8 decoder setup, drain logic, and flush lifecycle.
final class TokenDecoder {
  TokenDecoder({required List<String> stopSequences})
    : _assembler = StreamAssembler(stopSequences: stopSequences) {
    _byteSink =
        const Utf8Decoder(
          allowMalformed: true,
        ).startChunkedConversion(
          StringConversionSink.fromStringSink(
            ChunkedStringSink(_decodedChunks),
          ),
        );
  }

  final StreamAssembler _assembler;
  final List<String> _decodedChunks = [];
  late final Sink<List<int>> _byteSink;

  /// Whether a stop sequence has been detected.
  bool get stopped => _assembler.stopped;

  /// Feed raw token bytes. Returns a chunk to yield, or null.
  StreamChunk? feedBytes(List<int> bytes) {
    _byteSink.add(bytes);
    final piece = drainDecodedChunks(_decodedChunks);
    if (piece.isEmpty) {
      return _assembler.addEmptyToken();
    }
    return _assembler.addText(piece);
  }

  /// Record a token that produced no text (control token, empty bytes, EOG).
  StreamChunk? feedEmptyToken() => _assembler.addEmptyToken();

  /// Close the UTF-8 decoder, flush remaining text, and return final chunks.
  ///
  /// Must be called exactly once when the generation loop ends.
  List<StreamChunk> finish() {
    _byteSink.close();
    if (_decodedChunks.isNotEmpty) {
      _assembler.appendPending(drainDecodedChunks(_decodedChunks));
    }
    return _assembler.flush();
  }
}
