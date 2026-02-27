// MLX runtime — implements InferenceRuntime for the MLX inference backend.
// Uses the batch decoder path for all generation (single or multi-sequence).
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/inference_adapter.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_batch_decoder.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_bindings.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_client.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_handles.dart';
import 'package:cow_brain/src/adapters/stream_chunk.dart';
import 'package:cow_brain/src/adapters/token_decoder.dart';
import 'package:cow_brain/src/isolate/brain_isolate.dart';
import 'package:cow_brain/src/isolate/models.dart';

/// MLX inference runtime.
///
/// Plugs into [InferenceAdapter] via the [InferenceRuntime] interface. Uses
/// [MlxBatchCoordinator] for all generation — a single sequence is just the
/// degenerate case of a batch of 1.
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
    // Create the batch decoder + coordinator.
    _decoder = MlxBatchDecoder(
      client: client,
      handles: _handles,
      maxTokens: options.contextSize,
    );
    _coordinator = MlxBatchCoordinator(decoder: _decoder);
    _sequenceIds.add(0);
  }

  final MlxRuntimeOptions _options;
  final MlxClientApi _client;
  late final MlxHandles _handles;
  late MlxBatchDecoder _decoder;
  late MlxBatchCoordinator _coordinator;

  /// Registered sequence IDs.
  final Set<int> _sequenceIds = {};

  bool _disposed = false;

  @override
  int countTokens(String prompt, {required bool addBos}) {
    _ensureNotDisposed();
    return _client.tokenize(_handles, prompt, addSpecial: addBos).length;
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

    // Tokenize the full prompt.
    final promptTokens = _client.tokenize(
      _handles,
      prompt,
      addSpecial: addBos,
    );

    // Add this sequence to the batch and prefill.
    _coordinator.addAndPrefill(
      sequenceId,
      promptTokens,
      _options.samplingOptions,
    );

    final maxOutputTokens = _options.maxOutputTokensDefault;
    final decoder = TokenDecoder(stopSequences: stopSequences);

    try {
      for (var i = 0; i < maxOutputTokens; i += 1) {
        final bytes = await _coordinator.awaitStep(sequenceId);

        // null means EOG.
        if (bytes == null) break;

        final chunk = bytes.isEmpty
            ? decoder.feedEmptyToken()
            : decoder.feedBytes(bytes);
        if (chunk != null) yield chunk;
        if (decoder.stopped) break;
      }
    } finally {
      // Remove from batch if still active (e.g. stopped by stop sequence).
      _coordinator.removeSequence(sequenceId);
    }

    for (final chunk in decoder.finish()) {
      yield chunk;
    }
  }

  @override
  void createSequence(int sequenceId) {
    _ensureNotDisposed();
    if (_sequenceIds.contains(sequenceId)) {
      throw StateError('Sequence $sequenceId already exists');
    }
    _sequenceIds.add(sequenceId);
  }

  @override
  void destroySequence(int sequenceId) {
    _ensureNotDisposed();
    _ensureSequenceExists(sequenceId);
    _sequenceIds.remove(sequenceId);
  }

  @override
  void forkSequence({required int source, required int target}) {
    _ensureNotDisposed();
    _ensureSequenceExists(source);
    if (_sequenceIds.contains(target)) {
      throw StateError('Target sequence $target already exists');
    }
    // TODO(mlx): The batch context doesn't support forking mid-flight.
    // For now, just register the sequence — it will re-prefill on generate().
    _sequenceIds.add(target);
  }

  /// Expose the batch decoder for direct use (e.g. tests).
  MlxBatchDecoder get batchDecoder => _decoder;

  @override
  void dispose() {
    if (_disposed) return;
    _decoder.dispose();
    _sequenceIds.clear();
    _disposed = true;
  }

  @override
  void reset() {
    _ensureNotDisposed();
    // Dispose old decoder, create fresh one.
    _decoder.dispose();
    _decoder = MlxBatchDecoder(
      client: _client,
      handles: _handles,
      maxTokens: _options.contextSize,
    );
    _coordinator = MlxBatchCoordinator(decoder: _decoder);
    _sequenceIds
      ..clear()
      ..add(0);
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('MlxRuntime is already disposed');
    }
  }

  void _ensureSequenceExists(int sequenceId) {
    if (!_sequenceIds.contains(sequenceId)) {
      throw StateError('Sequence $sequenceId does not exist');
    }
  }
}
