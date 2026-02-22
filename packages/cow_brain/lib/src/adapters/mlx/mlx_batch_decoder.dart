// Batch coordination for multi-sequence MLX GPU decoding.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/mlx/mlx_client.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_handles.dart';
import 'package:cow_brain/src/isolate/models.dart';

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
