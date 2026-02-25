// Batch coordination for multi-sequence MLX GPU decoding.
// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:cow_brain/src/adapters/mlx/mlx_client.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_handles.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:meta/meta.dart';

/// Coordinates batched decoding across multiple sequences using MLX.
///
/// Unlike `LlamaBatchDecoder` which collects per-sequence tokens and
/// dispatches a single decode, the MLX batch context manages all
/// sequences natively. Each [step] call runs a single forward pass
/// for the entire batch and returns per-sequence token bytes.
class MlxBatchDecoder {
  MlxBatchDecoder({
    required MlxClientApi client,
    required MlxHandles handles,
    required int maxTokens,
  }) : _client = client,
       _handles = handles {
    _batchHandle = _client.batchCreate(handles, maxTokens);
  }

  final MlxClientApi _client;
  final MlxHandles _handles;
  late final int _batchHandle;

  /// Queue a sequence for the next prefill.
  void addSequence(int seqId, List<int> tokens) {
    _client.batchAddSequence(_handles, _batchHandle, seqId, tokens);
  }

  /// Prefill all pending sequences. Returns the number of active sequences.
  int prefill(SamplingOptions options) {
    return _client.batchPrefill(_handles, _batchHandle, options);
  }

  /// One decode step for all active sequences.
  ///
  /// Returns a map of seqId → raw token bytes.
  /// A `null` value means the sequence hit an EOG token.
  Map<int, List<int>?> step({int maxSeqs = 16, int bufferSize = 4096}) {
    return _client.batchStep(
      _handles,
      _batchHandle,
      maxSeqs: maxSeqs,
      bufferSize: bufferSize,
    );
  }

  /// Remove a completed sequence from the batch.
  void removeSequence(int seqId) {
    _client.batchRemoveSequence(_handles, _batchHandle, seqId);
  }

  /// Number of actively generating sequences.
  int get activeCount => _client.batchActiveCount(_handles, _batchHandle);

  /// Free the batch context.
  void dispose() {
    _client.batchFree(_handles, _batchHandle);
  }
}

/// Coalescing layer on top of [MlxBatchDecoder].
///
/// Each sequence's generate loop calls [awaitStep] to wait for the next
/// batched forward pass. Uses [Timer.run] to coalesce — all sequences that
/// call [awaitStep] within the same event loop tick share one step call.
class MlxBatchCoordinator {
  MlxBatchCoordinator({required MlxBatchDecoder decoder}) : _decoder = decoder;

  final MlxBatchDecoder _decoder;
  final Map<int, Completer<List<int>?>> _waiting = {};
  bool _dispatchScheduled = false;

  /// The set of sequence IDs that have been added and prefilled.
  final Set<int> _activeSeqs = {};

  /// Add a sequence, prefill it, and mark it active.
  void addAndPrefill(int seqId, List<int> tokens, SamplingOptions options) {
    _decoder
      ..addSequence(seqId, tokens)
      ..prefill(options);
    _activeSeqs.add(seqId);
  }

  /// Await the next batch decode step for [seqId].
  ///
  /// Returns raw token bytes, or `null` if the sequence hit EOG.
  Future<List<int>?> awaitStep(int seqId) {
    final completer = Completer<List<int>?>();
    _waiting[seqId] = completer;

    if (!_dispatchScheduled) {
      _dispatchScheduled = true;
      Timer.run(_dispatch);
    }

    return completer.future;
  }

  /// Remove a completed sequence from the batch. Idempotent.
  void removeSequence(int seqId) {
    if (_activeSeqs.remove(seqId)) {
      _decoder.removeSequence(seqId);
    }
  }

  /// Number of actively generating sequences.
  int get activeCount => _activeSeqs.length;

  void _dispatch() {
    _dispatchScheduled = false;
    if (_waiting.isEmpty) return;

    final waiters = Map<int, Completer<List<int>?>>.of(_waiting);
    _waiting.clear();

    try {
      final results = _decoder.step(maxSeqs: _activeSeqs.length);

      for (final entry in waiters.entries) {
        final seqId = entry.key;
        final completer = entry.value;
        final bytes = results[seqId];

        if (bytes == null) {
          // EOG — remove from batch.
          _activeSeqs.remove(seqId);
          _decoder.removeSequence(seqId);
        }

        completer.complete(bytes);
      }
    } catch (e, st) {
      for (final completer in waiters.values) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      }
    }
  }

  @visibleForTesting
  void dispatchNow() => _dispatch();
}
