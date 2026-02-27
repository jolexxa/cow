// Batch coordination for multi-sequence prompt prefill.
// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:cow_brain/src/adapters/llama/llama_batch_decoder.dart';
import 'package:cow_brain/src/adapters/llama/llama_client.dart';
import 'package:cow_brain/src/adapters/llama/llama_handles.dart';
import 'package:meta/meta.dart';

/// Coordinates batched prefill across multiple sequences.
///
/// Each sequence's generate call submits its prompt tokens via
/// [submitPrefill]. The batcher collects all submissions within one event
/// loop tick and dispatches a single `decodeBatch` call containing all of
/// them — exactly like [LlamaBatchDecoder] does for token-by-token decode.
///
/// Uses [Timer.run] (event queue) rather than [scheduleMicrotask] so that
/// other sequences have a chance to submit before dispatch fires.
class LlamaPrefillBatcher {
  LlamaPrefillBatcher({
    required LlamaClientApi client,
    required LlamaHandles handles,
    required int nBatch,
  }) : _client = client,
       _handles = handles,
       _nBatch = nBatch;

  final LlamaClientApi _client;
  final LlamaHandles _handles;
  final int _nBatch;

  final List<_PrefillSubmission> _pending = [];
  bool _dispatchScheduled = false;

  /// Submit prompt tokens for batched prefill.
  ///
  /// Returns a [Future] that completes with the batch index of the last
  /// token for this sequence (where logits are available for sampling).
  Future<BatchDecodeResult> submitPrefill({
    required int sequenceId,
    required List<int> tokens,
  }) {
    if (tokens.isEmpty) {
      return Future.value(BatchDecodeResult(batchIndex: -1));
    }

    final completer = Completer<BatchDecodeResult>();
    _pending.add(
      _PrefillSubmission(
        sequenceId: sequenceId,
        tokens: tokens,
        completer: completer,
      ),
    );

    if (!_dispatchScheduled) {
      _dispatchScheduled = true;
      Timer.run(_dispatch);
    }

    return completer.future;
  }

  void _dispatch() {
    _dispatchScheduled = false;
    if (_pending.isEmpty) return;

    final submissions = List<_PrefillSubmission>.of(_pending);
    _pending.clear();

    final b = _handles.bindings;
    final mem = b.llama_get_memory(_handles.context);

    // Build two lists: non-final tokens (logits: false) and final tokens
    // (logits: true, one per sequence). We process all non-final tokens
    // first in chunks, then dispatch all final tokens in a single batch.
    // This ensures every sequence's logits survive in the last decode call.
    final prefillEntries = <({int token, int pos, int seqId, bool logits})>[];
    final finalEntries = <({int token, int pos, int seqId, bool logits})>[];

    for (final s in submissions) {
      final posMax = b.llama_memory_seq_pos_max(mem, s.sequenceId);
      final startPos = posMax + 1;

      for (var i = 0; i < s.tokens.length; i++) {
        final isLast = i == s.tokens.length - 1;
        final entry = (
          token: s.tokens[i],
          pos: startPos + i,
          seqId: s.sequenceId,
          logits: isLast,
        );
        if (isLast) {
          finalEntries.add(entry);
        } else {
          prefillEntries.add(entry);
        }
      }
    }

    try {
      // 1) Dispatch all non-final tokens in chunks (no logits needed).
      if (prefillEntries.isNotEmpty) {
        _dispatchChunked(prefillEntries);
      }

      // 2) Dispatch all final tokens in one batch. Each sequence contributes
      //    exactly one entry, so this easily fits within nBatch.
      _client.decodeBatch(_handles, _handles.context, finalEntries);

      // Batch indices are simply 0, 1, 2, ... into the final batch.
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

  /// Dispatch entries in fixed-size chunks that respect [_nBatch].
  ///
  /// All entries passed here have `logits: false` — final tokens (with
  /// logits) are dispatched separately by [_dispatch].
  void _dispatchChunked(
    List<({int token, int pos, int seqId, bool logits})> entries,
  ) {
    for (var i = 0; i < entries.length; i += _nBatch) {
      final end = (i + _nBatch < entries.length) ? i + _nBatch : entries.length;
      _client.decodeBatch(
        _handles,
        _handles.context,
        entries.sublist(i, end),
      );
    }
  }

  @visibleForTesting
  void dispatchNow() => _dispatch();
}

class _PrefillSubmission {
  _PrefillSubmission({
    required this.sequenceId,
    required this.tokens,
    required this.completer,
  });

  final int sequenceId;
  final List<int> tokens;
  final Completer<BatchDecodeResult> completer;
}
