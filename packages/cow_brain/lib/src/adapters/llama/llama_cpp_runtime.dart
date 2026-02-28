// This is the native llama.cpp runtime; docs can be expanded later.
// Plain string composition keeps the streaming logic straightforward.

import 'dart:ffi';
import 'dart:math' show min;

import 'package:cow_brain/src/adapters/inference_adapter.dart';
import 'package:cow_brain/src/adapters/llama/llama_batch_decoder.dart';
import 'package:cow_brain/src/adapters/llama/llama_bindings.dart';
import 'package:cow_brain/src/adapters/llama/llama_client.dart';
import 'package:cow_brain/src/adapters/llama/llama_handles.dart';
import 'package:cow_brain/src/adapters/llama/llama_model_metadata.dart';
import 'package:cow_brain/src/adapters/llama/llama_prefill_batcher.dart';
import 'package:cow_brain/src/adapters/stream_chunk.dart';
import 'package:cow_brain/src/adapters/token_decoder.dart';
import 'package:cow_brain/src/isolate/brain_isolate.dart';
import 'package:cow_brain/src/isolate/models.dart';

/// Per-sequence state bundling BOS tracking and cached token history.
final class SequenceState {
  /// Creates a new, empty sequence state.
  SequenceState();

  /// Creates a copy of [other].
  SequenceState.from(SequenceState other)
    : bosApplied = other.bosApplied,
      cachedTokens = List<int>.of(other.cachedTokens);

  /// Whether the beginning-of-sequence token has been applied.
  bool bosApplied = false;

  /// Tokens that have already been fed into the KV cache.
  List<int> cachedTokens = [];

  /// Resets the sequence state to its initial values.
  void reset() {
    bosApplied = false;
    cachedTokens = [];
  }

  /// Trims cached tokens to [length], discarding the rest.
  void trimCacheTo(int length) {
    cachedTokens = length >= cachedTokens.length
        ? cachedTokens
        : cachedTokens.sublist(0, length);
  }

  /// Drops [count] tokens from the front of the cache.
  void dropCacheFront(int count) {
    cachedTokens = count >= cachedTokens.length
        ? []
        : cachedTokens.sublist(count);
  }
}

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
    _prefillBatcher = LlamaPrefillBatcher(
      client: _client,
      handles: _handles,
      nBatch: options.contextOptions.nBatch,
    );
  }

  final LlamaCppRuntimeOptions _options;
  final LlamaClientApi _client;
  late final LlamaHandles _handles;
  late final LlamaBatchDecoder _batchDecoder;
  late final LlamaPrefillBatcher _prefillBatcher;

  bool _disposed = false;
  final Map<int, SequenceState> _sequences = {0: SequenceState()};

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
    // Always count conservatively (as if BOS not yet applied). At worst we
    // overestimate by one token, which is safe for budget estimation. The
    // alternative — using a specific sequence's bos state — was incorrect
    // because the context manager is sequence-agnostic.
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
    int sequenceId = 0,
  }) async* {
    _ensureNotDisposed();
    _ensureSequenceExists(sequenceId);
    final seq = _sequences[sequenceId]!;

    if (requiresReset) {
      _resetSequence(sequenceId);
    }

    final promptTokens = _client.tokenize(
      _handles,
      prompt,
      addSpecial: addBos && !seq.bosApplied,
    );
    if (addBos) {
      seq.bosApplied = true;
    }

    // Find common prefix and trim diverged KV cache entries.
    final commonPrefixLen = _commonPrefixLengthFor(
      promptTokens,
      seq.cachedTokens,
    );
    _trimDivergedCache(seq, sequenceId, commonPrefixLen);

    final newTokens = promptTokens.sublist(commonPrefixLen);

    final maxOutputTokens = _options.maxOutputTokensDefault;
    final dropped = _ensureRoomFor(
      sequenceId,
      newTokens.length,
      maxOutputTokens,
    );
    if (dropped > 0) {
      seq.dropCacheFront(dropped);
    }
    // Submit prefill for batched decode. The await yields to the event loop,
    // letting other concurrent generate() calls reach their own submitPrefill.
    // Timer.run then batches all of them into a single decodeBatch FFI call.
    int? lastBatchIndex;
    if (newTokens.isNotEmpty) {
      final prefillResult = await _prefillBatcher.submitPrefill(
        sequenceId: sequenceId,
        tokens: newTokens,
      );
      lastBatchIndex = prefillResult.batchIndex;
    }
    seq.cachedTokens = [...seq.cachedTokens, ...newTokens];

    final sampler = _buildSampler();
    final decoder = TokenDecoder(stopSequences: stopSequences);

    try {
      for (var i = 0; i < maxOutputTokens; i += 1) {
        // Sample from the correct logit position: explicit batch index
        // after batched prefill or decode, or -1 (last position) when
        // newTokens was empty (full cache hit).
        final token = lastBatchIndex != null
            ? _client.sampleAt(_handles, sampler, lastBatchIndex)
            : _client.sampleNext(_handles, sampler);

        if (_handles.bindings.llama_vocab_is_eog(_handles.vocab, token)) {
          break;
        }

        // Submit token for batched decode. This awaits dispatch, which
        // naturally yields to the event loop (replacing _asyncBoundary).
        final result = await _batchDecoder.submitToken(
          token: token,
          sequenceId: sequenceId,
        );
        lastBatchIndex = result.batchIndex;
        seq.cachedTokens.add(token);

        final chunk = _decodeToken(token, decoder);
        if (chunk != null) yield chunk;
        if (decoder.stopped) break;
      }
    } finally {
      sampler.dispose();
    }

    for (final chunk in decoder.finish()) {
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
    if (_sequences.containsKey(sequenceId)) {
      throw StateError('Sequence $sequenceId already exists');
    }
    _sequences[sequenceId] = SequenceState();
  }

  @override
  void destroySequence(int sequenceId) {
    _ensureNotDisposed();
    _ensureSequenceExists(sequenceId);
    _clearSequenceKv(sequenceId);
    _sequences.remove(sequenceId);
  }

  @override
  void forkSequence({required int source, required int target}) {
    _ensureNotDisposed();
    _ensureSequenceExists(source);
    if (_sequences.containsKey(target)) {
      throw StateError('Target sequence $target already exists');
    }
    // TODO(llama.cpp): seq_cp requires "full" (non-split) KV buffers, which
    // aren't available when maxSequences > 1. For now, create a fresh sequence
    // with an empty cache — the next generate() call will re-prefill via
    // prefix matching. Replace with seq_cp when upstream supports it.
    _sequences[target] = SequenceState.from(_sequences[source]!)
      ..cachedTokens = [];
  }

  @override
  void reset() {
    _ensureNotDisposed();
    _client.resetContext(
      _handles,
      _options.contextOptions,
      maxSequences: _options.maxSequences,
    );
    _sequences
      ..clear()
      ..[0] = SequenceState();
  }

  void _resetSequence(int sequenceId) {
    _clearSequenceKv(sequenceId);
    _sequences[sequenceId]!.reset();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('LlamaCppRuntime is already disposed');
    }
  }

  void _ensureSequenceExists(int sequenceId) {
    if (!_sequences.containsKey(sequenceId)) {
      throw StateError('Sequence $sequenceId does not exist');
    }
  }

  /// Returns the KV cache position bounds for [sequenceId].
  ({int posMin, int posMax}) _sequenceBounds(int sequenceId) {
    final b = _handles.bindings;
    final mem = b.llama_get_memory(_handles.context);
    return (
      posMin: b.llama_memory_seq_pos_min(mem, sequenceId),
      posMax: b.llama_memory_seq_pos_max(mem, sequenceId),
    );
  }

  /// Removes all KV cache entries for [sequenceId].
  void _clearSequenceKv(int sequenceId) {
    final (:posMin, :posMax) = _sequenceBounds(sequenceId);
    if (posMin >= 0 && posMax >= posMin) {
      final b = _handles.bindings;
      final mem = b.llama_get_memory(_handles.context);
      b.llama_memory_seq_rm(mem, sequenceId, posMin, posMax + 1);
    }
  }

  /// Trims KV cache entries that diverge after [commonPrefixLen],
  /// and updates [seq]'s cached token list.
  void _trimDivergedCache(
    SequenceState seq,
    int sequenceId,
    int commonPrefixLen,
  ) {
    if (commonPrefixLen >= seq.cachedTokens.length) return;
    final posMax = _sequenceBounds(sequenceId).posMax;
    if (posMax >= commonPrefixLen) {
      final b = _handles.bindings;
      final mem = b.llama_get_memory(_handles.context);
      b.llama_memory_seq_rm(mem, sequenceId, commonPrefixLen, posMax + 1);
    }
    seq.trimCacheTo(commonPrefixLen);
  }

  /// Builds a sampler chain from the runtime's sampling options.
  LlamaSamplerChain _buildSampler() {
    final opts = _options.samplingOptions;
    return LlamaSamplerChain.build(
      _handles.bindings,
      SamplingOptions(
        seed: opts.seed,
        topK: opts.topK,
        topP: opts.topP,
        minP: opts.minP,
        temperature: opts.temperature ?? 0.7,
        typicalP: opts.typicalP,
        penaltyRepeat: opts.penaltyRepeat,
        penaltyLastN: opts.penaltyLastN,
      ),
    );
  }

  /// Decodes [token] bytes and feeds them to [decoder].
  StreamChunk? _decodeToken(int token, TokenDecoder decoder) {
    if (_handles.bindings.llama_vocab_is_control(_handles.vocab, token)) {
      return decoder.feedEmptyToken();
    }
    final bytes = _client.tokenToBytes(_handles, token);
    return bytes.isEmpty ? decoder.feedEmptyToken() : decoder.feedBytes(bytes);
  }

  int _ensureRoomFor(
    int sequenceId,
    int promptTokens,
    int maxOutputTokens,
  ) {
    final (:posMin, :posMax) = _sequenceBounds(sequenceId);
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
    final b = _handles.bindings;
    final mem = b.llama_get_memory(_handles.context);
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
}
