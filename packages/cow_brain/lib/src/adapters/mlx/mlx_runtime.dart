// MLX runtime — implements InferenceRuntime for the MLX inference backend.
// Uses Apple's TokenIterator (via cow_mlx_generate_begin/next) for
// prefill, sampling, and streaming detokenization. The Dart side only
// handles stop-sequence detection and stream chunking.
// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:cow_brain/src/adapters/inference_adapter.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_bindings.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_client.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_handles.dart';
import 'package:cow_brain/src/adapters/stream_assembler.dart';
import 'package:cow_brain/src/adapters/stream_chunk.dart';
import 'package:cow_brain/src/isolate/brain_isolate.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:meta/meta.dart';

/// MLX inference runtime.
///
/// Plugs into [InferenceAdapter] via the [InferenceRuntime] interface. The
/// prompt formatting and stream parsing layers are backend-agnostic, so they
/// work identically for both llama.cpp and MLX.
final class MlxRuntime implements InferenceRuntime, BrainRuntime {
  MlxRuntime({
    required int modelId,
    required MlxRuntimeOptions options,
    required MlxClientApi client,
    required MlxBindings bindings,
  }) : _options = options,
       _client = client {
    _handles = MlxHandles.fromModelId(
      modelId: modelId,
      bindings: bindings,
    );
    _handles.contextHandle = _client.createContext(
      _handles,
      options.contextSize,
    );
  }

  final MlxRuntimeOptions _options;
  final MlxClientApi _client;
  late final MlxHandles _handles;

  bool _disposed = false;

  @override
  int countTokens(String prompt, {required bool addBos}) {
    _ensureNotDisposed();
    final tokens = _client.tokenize(
      _handles,
      prompt,
      addSpecial: addBos,
    );
    return tokens.length;
  }

  @override
  Stream<StreamChunk> generate({
    required String prompt,
    required List<String> stopSequences,
    required bool addBos,
    required bool requiresReset,
    required int reusePrefixMessageCount,
  }) async* {
    _ensureNotDisposed();

    if (requiresReset) {
      _client.resetContext(_handles, _options.contextSize);
    }

    // Tokenize the full prompt every time. The native side compares
    // incoming tokens against its cached sequence to find the common
    // prefix, trims diverged entries, and only prefills new tokens.
    final promptTokens = _client.tokenize(
      _handles,
      prompt,
      addSpecial: addBos,
    );

    // Begin generation — native handles cache dedup internally.
    _client.generateBegin(
      _handles,
      promptTokens,
      _options.samplingOptions,
    );

    final maxOutputTokens = _options.maxOutputTokensDefault;
    final assembler = StreamAssembler(stopSequences: stopSequences);

    // Chunked UTF-8 decoder — same pattern as LlamaCppRuntime.
    // Raw token bytes from the native side may contain partial UTF-8
    // sequences; the decoder buffers them until complete.
    final decodedChunks = <String>[];
    final chunkSink = StringConversionSink.fromStringSink(
      _ChunkedStringSink(decodedChunks),
    );
    final byteSink = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(chunkSink);

    try {
      for (var i = 0; i < maxOutputTokens; i += 1) {
        final bytes = _client.generateNext(_handles);

        // null means generation is done (EOG or max tokens).
        if (bytes == null) break;

        if (bytes.isEmpty) {
          final chunk = assembler.addEmptyToken();
          if (chunk != null) {
            yield chunk;
            await _asyncBoundary();
          }
          continue;
        }

        byteSink.add(bytes);
        if (decodedChunks.isEmpty) {
          final chunk = assembler.addEmptyToken(); // coverage:ignore-line
          if (chunk != null) {
            yield chunk; // coverage:ignore-line
            await _asyncBoundary(); // coverage:ignore-line
          }
          continue;
        }

        final piece = _drainDecodedChunks(decodedChunks);
        if (piece.isEmpty) {
          final chunk = assembler.addEmptyToken();
          if (chunk != null) {
            yield chunk; // coverage:ignore-line
            await _asyncBoundary(); // coverage:ignore-line
          }
          continue;
        }

        final chunk = assembler.addText(piece);
        if (chunk != null) {
          yield chunk;
          await _asyncBoundary();
        }
        if (assembler.stopped) break;
      }
    } finally {
      byteSink.close();
      if (decodedChunks.isNotEmpty) {
        assembler.appendPending(_drainDecodedChunks(decodedChunks));
      }
    }

    for (final chunk in assembler.flush()) {
      yield chunk;
      await _asyncBoundary();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    if (_handles.contextHandle >= 0) {
      _handles.bindings.freeContext(_handles.contextHandle);
      _handles.contextHandle = -1;
    }
    _disposed = true;
  }

  @override
  void reset() {
    _ensureNotDisposed();
    _client.resetContext(_handles, _options.contextSize);
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('MlxRuntime is already disposed');
    }
  }

  Future<void> _asyncBoundary() => Future<void>.delayed(Duration.zero);
}

@visibleForTesting
String drainMlxDecodedChunks(List<String> decodedChunks) =>
    _drainDecodedChunks(decodedChunks);

@visibleForTesting
StringSink mlxChunkedStringSink(List<String> chunks) =>
    _ChunkedStringSink(chunks);

String _drainDecodedChunks(List<String> decodedChunks) {
  final piece = decodedChunks.length == 1
      ? decodedChunks.removeAt(0)
      : decodedChunks.join();
  if (decodedChunks.isNotEmpty) {
    decodedChunks.clear();
  }
  return piece;
}

final class _ChunkedStringSink implements StringSink {
  _ChunkedStringSink(this._chunks);

  final List<String> _chunks;

  @override
  void write(Object? obj) {
    if (obj == null) return;
    _chunks.add(obj.toString());
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    var first = true;
    for (final obj in objects) {
      if (!first && separator.isNotEmpty) _chunks.add(separator);
      first = false;
      if (obj == null) continue;
      _chunks.add(obj.toString());
    }
  }

  @override
  void writeCharCode(int charCode) {
    _chunks.add(String.fromCharCode(charCode));
  }

  @override
  void writeln([Object? obj = '']) {
    if (obj != null && obj.toString().isNotEmpty) _chunks.add(obj.toString());
    _chunks.add('\n');
  }
}
