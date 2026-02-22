// Batch coordination for multi-sequence GPU decoding.
// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:cow_brain/src/adapters/llama/llama_client.dart';
import 'package:cow_brain/src/adapters/llama/llama_handles.dart';
import 'package:meta/meta.dart';

/// Result of a batched decode for a single sequence.
class BatchDecodeResult {
  BatchDecodeResult({required this.batchIndex});

  /// The index within the batch where this sequence's logits are.
  final int batchIndex;
}

/// Coordinates batched decoding across multiple sequences.
///
/// Each sequence calls [submitToken] to queue its next token. The decoder
/// collects all submissions within one event loop tick and dispatches a
/// single `llama_decode` call containing all of them.
///
/// Uses [Timer.run] (event queue) rather than [scheduleMicrotask] so that
/// other sequences have a chance to submit before dispatch fires.
class LlamaBatchDecoder {
  LlamaBatchDecoder({
    required LlamaClientApi client,
    required LlamaHandles handles,
  }) : _client = client,
       _handles = handles;

  final LlamaClientApi _client;
  final LlamaHandles _handles;

  final List<_BatchSubmission> _pending = [];
  bool _dispatchScheduled = false;

  /// Submit a single token for batched decode.
  ///
  /// Returns a [Future] that completes with the batch index for sampling
  /// after the batch has been dispatched and decoded.
  Future<BatchDecodeResult> submitToken({
    required int token,
    required int sequenceId,
  }) {
    final completer = Completer<BatchDecodeResult>();
    _pending.add(_BatchSubmission(
      token: token,
      sequenceId: sequenceId,
      completer: completer,
    ));

    if (!_dispatchScheduled) {
      _dispatchScheduled = true;
      Timer.run(_dispatch);
    }

    return completer.future;
  }

  void _dispatch() {
    _dispatchScheduled = false;
    if (_pending.isEmpty) return;

    final submissions = List<_BatchSubmission>.of(_pending);
    _pending.clear();

    final b = _handles.bindings;
    final mem = b.llama_get_memory(_handles.context);

    final entries = <({int token, int pos, int seqId, bool logits})>[];
    for (final s in submissions) {
      final posMax = b.llama_memory_seq_pos_max(mem, s.sequenceId);
      entries.add((
        token: s.token,
        pos: posMax + 1,
        seqId: s.sequenceId,
        logits: true,
      ));
    }

    try {
      _client.decodeBatch(_handles, _handles.context, entries);

      for (var i = 0; i < submissions.length; i++) {
        submissions[i].completer.complete(
          BatchDecodeResult(batchIndex: i),
        );
      }
    } catch (e, st) {
      for (final s in submissions) {
        if (!s.completer.isCompleted) {
          s.completer.completeError(e, st);
        }
      }
    }
  }

  @visibleForTesting
  void dispatchNow() => _dispatch();
}

class _BatchSubmission {
  _BatchSubmission({
    required this.token,
    required this.sequenceId,
    required this.completer,
  });

  final int token;
  final int sequenceId;
  final Completer<BatchDecodeResult> completer;
}
