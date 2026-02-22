// This is the native llama.cpp runtime; docs can be expanded later.
// Plain string composition keeps the streaming logic straightforward.
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:ffi';

import 'package:meta/meta.dart';

import 'package:cow_brain/src/adapters/inference_adapter.dart';
import 'package:cow_brain/src/adapters/llama/llama_bindings.dart';
import 'package:cow_brain/src/adapters/llama/llama_client.dart';
import 'package:cow_brain/src/adapters/llama/llama_handles.dart';
import 'package:cow_brain/src/adapters/llama/llama_model_metadata.dart';
import 'package:cow_brain/src/adapters/stream_assembler.dart';
import 'package:cow_brain/src/adapters/stream_chunk.dart';
import 'package:cow_brain/src/isolate/brain_isolate.dart';
import 'package:cow_brain/src/isolate/models.dart';

/// Native llama.cpp runtime that powers the [InferenceAdapter].
///
/// Requires a preloaded model pointer from a model server isolate.
/// The runtime creates its own context but never loads models itself.
final class LlamaCppRuntime implements InferenceRuntime, BrainRuntime {
  /// Creates a runtime with a shared model pointer from another isolate.
  ///
  /// [modelPointer] is the address of a `llama_model*` loaded by ModelServer.
  /// [options] provides context/sampling configuration and library path.
  LlamaCppRuntime({
    required int modelPointer,
    required LlamaCppRuntimeOptions options,
    required LlamaClientApi client,
    required LlamaBindings bindings,
  }) : _options = options,
       _client = client {
    _handles = LlamaHandles.fromModelPointer(
      modelPointer: modelPointer,
      bindings: bindings,
    );
    _handles.context = _client.createContext(_handles, options.contextOptions);
    if (_handles.context == nullptr) {
      throw StateError('Failed to create llama context');
    }
  }

  final LlamaCppRuntimeOptions _options;
  final LlamaClientApi _client;
  late final LlamaHandles _handles;

  bool _disposed = false;
  bool _bosApplied = false;

  /// Reads the chat template from the loaded model's GGUF metadata.
  ///
  /// Returns null if no chat template is available.
  String? get chatTemplate {
    _ensureNotDisposed();
    final metadata = LlamaModelMetadata(
      bindings: _handles.bindings,
      model: _handles.model,
    );
    return metadata.chatTemplate;
  }

  @override
  int countTokens(String prompt, {required bool addBos}) {
    _ensureNotDisposed();
    final tokens = _client.tokenize(
      _handles,
      prompt,
      addSpecial: addBos && !_bosApplied,
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
      _client.resetContext(_handles, _options.contextOptions);
      _bosApplied = false;
    }

    final promptTokens = _client.tokenize(
      _handles,
      prompt,
      addSpecial: addBos && !_bosApplied,
    );
    if (addBos) {
      _bosApplied = true;
    }

    final maxOutputTokens = _options.maxOutputTokensDefault;
    _ensureRoomFor(promptTokens.length, maxOutputTokens);
    _decodeTokens(promptTokens);

    final temperature = _options.samplingOptions.temperature ?? 0.7;
    final samplingOptions = SamplingOptions(
      seed: _options.samplingOptions.seed,
      topK: _options.samplingOptions.topK,
      topP: _options.samplingOptions.topP,
      minP: _options.samplingOptions.minP,
      temperature: temperature,
      typicalP: _options.samplingOptions.typicalP,
      penaltyRepeat: _options.samplingOptions.penaltyRepeat,
      penaltyLastN: _options.samplingOptions.penaltyLastN,
    );
    final sampler = LlamaSamplerChain.build(_handles.bindings, samplingOptions);
    final assembler = StreamAssembler(stopSequences: stopSequences);

    final decodedChunks = <String>[];
    final chunkSink = StringConversionSink.fromStringSink(
      _ChunkedStringSink(decodedChunks),
    );
    final byteSink = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(chunkSink);

    try {
      for (var i = 0; i < maxOutputTokens; i += 1) {
        final token = _client.sampleNext(_handles, sampler);
        final b = _handles.bindings;
        if (b.llama_vocab_is_eog(_handles.vocab, token)) {
          break;
        }

        _client.decode(_handles, _handles.context, <int>[token]);

        if (b.llama_vocab_is_control(_handles.vocab, token)) {
          final chunk = assembler.addEmptyToken();
          if (chunk != null) {
            yield chunk;
            await _asyncBoundary();
          }
          continue;
        }
        final bytes = _client.tokenToBytes(_handles, token);
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
      sampler.dispose();
    }

    for (final chunk in assembler.flush()) {
      yield chunk;
      await _asyncBoundary();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    // Only free the context, not the shared model.
    // The model is owned by ModelServer and freed there.
    _handles.bindings.llama_free(_handles.context);
    _disposed = true;
  }

  @override
  void reset() {
    _ensureNotDisposed();
    _client.resetContext(_handles, _options.contextOptions);
    _bosApplied = false;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('LlamaCppRuntime is already disposed');
    }
  }

  void _ensureRoomFor(int promptTokens, int maxOutputTokens) {
    final b = _handles.bindings;
    final mem = b.llama_get_memory(_handles.context);

    final posMin = b.llama_memory_seq_pos_min(mem, 0);
    final posMax = b.llama_memory_seq_pos_max(mem, 0);
    final currentTokens = (posMin >= 0 && posMax >= posMin)
        ? (posMax - posMin + 1)
        : 0;

    final requiredTokens = promptTokens + maxOutputTokens;
    if (requiredTokens > _options.contextOptions.contextSize) {
      throw StateError(
        'Prompt too long for context ($promptTokens + $maxOutputTokens > '
        '${_options.contextOptions.contextSize})',
      );
    }

    final projectedTotal = currentTokens + requiredTokens;
    if (projectedTotal <= _options.contextOptions.contextSize) {
      return;
    }
    if (currentTokens == 0) {
      return;
    }

    final tokensToDrop = projectedTotal - _options.contextOptions.contextSize;
    if (tokensToDrop >= currentTokens) {
      b.llama_memory_seq_rm(mem, 0, posMin, posMax + 1);
      return;
    }

    final dropStart = posMin;
    final dropEnd = posMin + tokensToDrop;
    final removed = b.llama_memory_seq_rm(mem, 0, dropStart, dropEnd);
    if (!removed) {
      throw StateError('Failed to drop tokens from llama memory');
    }
  }

  void _decodeTokens(List<int> tokens) {
    if (tokens.isEmpty) {
      return;
    }
    final maxBatch = _options.contextOptions.nBatch;
    if (tokens.length <= maxBatch) {
      _client.decode(_handles, _handles.context, tokens);
      return;
    }
    for (var i = 0; i < tokens.length; i += maxBatch) {
      final end = (i + maxBatch < tokens.length) ? i + maxBatch : tokens.length;
      _client.decode(_handles, _handles.context, tokens.sublist(i, end));
    }
  }

  Future<void> _asyncBoundary() => Future<void>.delayed(Duration.zero);
}

String _drainDecodedChunks(List<String> decodedChunks) {
  final piece = decodedChunks.length == 1
      ? decodedChunks.removeAt(0)
      : decodedChunks.join();
  if (decodedChunks.isNotEmpty) {
    decodedChunks.clear();
  }
  return piece;
}

@visibleForTesting
String drainDecodedChunks(List<String> decodedChunks) =>
    _drainDecodedChunks(decodedChunks);

@visibleForTesting
StringSink llamaChunkedStringSink(List<String> chunks) =>
    _ChunkedStringSink(chunks);

final class _ChunkedStringSink implements StringSink {
  _ChunkedStringSink(this._chunks);

  final List<String> _chunks;

  @override
  void write(Object? obj) {
    if (obj == null) {
      return;
    }
    _chunks.add(obj.toString());
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    var first = true;
    for (final obj in objects) {
      if (!first && separator.isNotEmpty) {
        _chunks.add(separator);
      }
      first = false;
      if (obj == null) {
        continue;
      }
      _chunks.add(obj.toString());
    }
  }

  @override
  void writeCharCode(int charCode) {
    _chunks.add(String.fromCharCode(charCode));
  }

  @override
  void writeln([Object? obj = '']) {
    if (obj != null && obj.toString().isNotEmpty) {
      _chunks.add(obj.toString());
    }
    _chunks.add('\n');
  }
}
