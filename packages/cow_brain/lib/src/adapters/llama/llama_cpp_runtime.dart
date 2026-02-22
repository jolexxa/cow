// This is the native llama.cpp runtime; docs can be expanded later.
// Plain string composition keeps the streaming logic straightforward.
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:ffi';
import 'dart:math' show min;

import 'package:cow_brain/src/adapters/inference_adapter.dart';
import 'package:cow_brain/src/adapters/llama/llama_batch_decoder.dart';
import 'package:cow_brain/src/adapters/llama/llama_bindings.dart';
import 'package:cow_brain/src/adapters/llama/llama_client.dart';
import 'package:cow_brain/src/adapters/llama/llama_handles.dart';
import 'package:cow_brain/src/adapters/llama/llama_model_metadata.dart';
import 'package:cow_brain/src/adapters/stream_assembler.dart';
import 'package:cow_brain/src/adapters/stream_chunk.dart';
import 'package:cow_brain/src/isolate/brain_isolate.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:meta/meta.dart';

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
    _handles.context = _client.createContext(
      _handles,
      options.contextOptions,
      maxSequences: options.maxSequences,
    );
    if (_handles.context == nullptr) {
      throw StateError('Failed to create llama context');
    }
    _batchDecoder = LlamaBatchDecoder(
      client: _client,
      handles: _handles,
    );
  }

  final LlamaCppRuntimeOptions _options;
  final LlamaClientApi _client;
  late final LlamaHandles _handles;
  late final LlamaBatchDecoder _batchDecoder;

  bool _disposed = false;
  final Map<int, bool> _bosApplied = {0: false};
  final Map<int, List<int>> _cachedTokens = {0: []};

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
    // Use sequence 0's bos state for budget estimation.
    final bos = _bosApplied[0] ?? false;
    final tokens = _client.tokenize(
      _handles,
      prompt,
      addSpecial: addBos && !bos,
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
    int sequenceId = 0,
  }) async* {
    _ensureNotDisposed();
    _ensureSequenceExists(sequenceId);

    if (requiresReset) {
      _resetSequence(sequenceId);
    }

    final seqBos = _bosApplied[sequenceId]!;
    final promptTokens = _client.tokenize(
      _handles,
      prompt,
      addSpecial: addBos && !seqBos,
    );
    if (addBos) {
      _bosApplied[sequenceId] = true;
    }

    final seqCached = _cachedTokens[sequenceId]!;

    // Find common prefix between cached and new prompt tokens.
    final commonPrefixLen = _commonPrefixLengthFor(promptTokens, seqCached);

    // Trim diverged tokens from the KV cache.
    if (commonPrefixLen < seqCached.length) {
      final b = _handles.bindings;
      final mem = b.llama_get_memory(_handles.context);
      final posMax = b.llama_memory_seq_pos_max(mem, sequenceId);
      if (posMax >= commonPrefixLen) {
        b.llama_memory_seq_rm(
          mem,
          sequenceId,
          commonPrefixLen,
          posMax + 1,
        );
      }
      _cachedTokens[sequenceId] = seqCached.sublist(0, commonPrefixLen);
    }

    final newTokens = promptTokens.sublist(commonPrefixLen);

    final maxOutputTokens = _options.maxOutputTokensDefault;
    final dropped = _ensureRoomFor(
      sequenceId,
      newTokens.length,
      maxOutputTokens,
    );
    if (dropped > 0) {
      final current = _cachedTokens[sequenceId]!;
      _cachedTokens[sequenceId] = dropped >= current.length
          ? []
          : current.sublist(dropped);
    }
    _decodeTokens(newTokens, sequenceId: sequenceId);
    _cachedTokens[sequenceId] = [
      ..._cachedTokens[sequenceId]!,
      ...newTokens,
    ];

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

    int? lastBatchIndex;

    try {
      for (var i = 0; i < maxOutputTokens; i += 1) {
        // Sample from the correct logit position: explicit batch index
        // after batched decode, or -1 (last position) after prefill.
        final token = lastBatchIndex != null
            ? _client.sampleAt(_handles, sampler, lastBatchIndex)
            : _client.sampleNext(_handles, sampler);

        final b = _handles.bindings;
        if (b.llama_vocab_is_eog(_handles.vocab, token)) {
          break;
        }

        // Submit token for batched decode. This awaits dispatch, which
        // naturally yields to the event loop (replacing _asyncBoundary).
        final result = await _batchDecoder.submitToken(
          token: token,
          sequenceId: sequenceId,
        );
        lastBatchIndex = result.batchIndex;
        _cachedTokens[sequenceId]!.add(token);

        if (b.llama_vocab_is_control(_handles.vocab, token)) {
          final chunk = assembler.addEmptyToken();
          if (chunk != null) {
            yield chunk;
          }
          continue;
        }
        final bytes = _client.tokenToBytes(_handles, token);
        if (bytes.isEmpty) {
          final chunk = assembler.addEmptyToken();
          if (chunk != null) {
            yield chunk;
          }
          continue;
        }
        byteSink.add(bytes);
        if (decodedChunks.isEmpty) {
          final chunk = assembler.addEmptyToken(); // coverage:ignore-line
          if (chunk != null) {
            yield chunk; // coverage:ignore-line
          }
          continue;
        }
        final piece = _drainDecodedChunks(decodedChunks);
        if (piece.isEmpty) {
          final chunk = assembler.addEmptyToken();
          if (chunk != null) {
            yield chunk; // coverage:ignore-line
          }
          continue;
        }

        final chunk = assembler.addText(piece);
        if (chunk != null) {
          yield chunk;
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
  void createSequence(int sequenceId) {
    _ensureNotDisposed();
    if (_cachedTokens.containsKey(sequenceId)) {
      throw StateError('Sequence $sequenceId already exists');
    }
    _cachedTokens[sequenceId] = [];
    _bosApplied[sequenceId] = false;
  }

  @override
  void destroySequence(int sequenceId) {
    _ensureNotDisposed();
    _ensureSequenceExists(sequenceId);
    // Remove KV cache for this sequence.
    final b = _handles.bindings;
    final mem = b.llama_get_memory(_handles.context);
    final posMin = b.llama_memory_seq_pos_min(mem, sequenceId);
    final posMax = b.llama_memory_seq_pos_max(mem, sequenceId);
    if (posMin >= 0 && posMax >= posMin) {
      b.llama_memory_seq_rm(mem, sequenceId, posMin, posMax + 1);
    }
    _cachedTokens.remove(sequenceId);
    _bosApplied.remove(sequenceId);
  }

  @override
  void forkSequence({required int source, required int target}) {
    _ensureNotDisposed();
    _ensureSequenceExists(source);
    if (_cachedTokens.containsKey(target)) {
      throw StateError('Target sequence $target already exists');
    }
    // Copy KV cache from source to target.
    final b = _handles.bindings;
    final mem = b.llama_get_memory(_handles.context);
    final posMin = b.llama_memory_seq_pos_min(mem, source);
    final posMax = b.llama_memory_seq_pos_max(mem, source);
    if (posMin >= 0 && posMax >= posMin) {
      b.llama_memory_seq_cp(mem, source, target, posMin, posMax + 1);
    }
    _cachedTokens[target] = List<int>.of(_cachedTokens[source]!);
    _bosApplied[target] = _bosApplied[source]!;
  }

  @override
  void reset() {
    _ensureNotDisposed();
    _client.resetContext(_handles, _options.contextOptions);
    _cachedTokens.clear();
    _bosApplied.clear();
    _cachedTokens[0] = [];
    _bosApplied[0] = false;
  }

  void _resetSequence(int sequenceId) {
    final b = _handles.bindings;
    final mem = b.llama_get_memory(_handles.context);
    final posMin = b.llama_memory_seq_pos_min(mem, sequenceId);
    final posMax = b.llama_memory_seq_pos_max(mem, sequenceId);
    if (posMin >= 0 && posMax >= posMin) {
      b.llama_memory_seq_rm(mem, sequenceId, posMin, posMax + 1);
    }
    _cachedTokens[sequenceId] = [];
    _bosApplied[sequenceId] = false;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('LlamaCppRuntime is already disposed');
    }
  }

  void _ensureSequenceExists(int sequenceId) {
    if (!_cachedTokens.containsKey(sequenceId)) {
      throw StateError('Sequence $sequenceId does not exist');
    }
  }

  int _ensureRoomFor(
    int sequenceId,
    int promptTokens,
    int maxOutputTokens,
  ) {
    final b = _handles.bindings;
    final mem = b.llama_get_memory(_handles.context);

    final posMin = b.llama_memory_seq_pos_min(mem, sequenceId);
    final posMax = b.llama_memory_seq_pos_max(mem, sequenceId);
    final currentTokens = (posMin >= 0 && posMax >= posMin)
        ? (posMax - posMin + 1)
        : 0;

    // With multiple sequences, the KV cache is shared — each sequence
    // gets contextSize ~/ maxSequences worth of budget.
    final perSeqBudget =
        _options.contextOptions.contextSize ~/ _options.maxSequences;

    final requiredTokens = promptTokens + maxOutputTokens;
    if (requiredTokens > perSeqBudget) {
      throw StateError(
        'Prompt too long for per-sequence budget '
        '($promptTokens + $maxOutputTokens > $perSeqBudget)',
      );
    }

    final projectedTotal = currentTokens + requiredTokens;
    if (projectedTotal <= perSeqBudget) {
      return 0;
    }
    if (currentTokens == 0) {
      return 0;
    }

    final tokensToDrop = projectedTotal - perSeqBudget;
    if (tokensToDrop >= currentTokens) {
      b.llama_memory_seq_rm(mem, sequenceId, posMin, posMax + 1);
      return currentTokens;
    }

    final dropStart = posMin;
    final dropEnd = posMin + tokensToDrop;
    final removed = b.llama_memory_seq_rm(
      mem,
      sequenceId,
      dropStart,
      dropEnd,
    );
    if (!removed) {
      throw StateError('Failed to drop tokens from llama memory');
    }
    return tokensToDrop;
  }

  int _commonPrefixLengthFor(List<int> tokens, List<int> cached) {
    final limit = min(tokens.length, cached.length);
    for (var i = 0; i < limit; i++) {
      if (tokens[i] != cached[i]) return i;
    }
    return limit;
  }

  void _decodeTokens(List<int> tokens, {required int sequenceId}) {
    if (tokens.isEmpty) {
      return;
    }
    final maxBatch = _options.contextOptions.nBatch;
    if (tokens.length <= maxBatch) {
      _client.decode(
        _handles,
        _handles.context,
        tokens,
        sequenceId: sequenceId,
      );
      return;
    }
    for (var i = 0; i < tokens.length; i += maxBatch) {
      final end = (i + maxBatch < tokens.length) ? i + maxBatch : tokens.length;
      _client.decode(
        _handles,
        _handles.context,
        tokens.sublist(i, end),
        sequenceId: sequenceId,
      );
    }
  }
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
