// Shared stream assembly logic for stop detection and chunked yielding.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/stream_chunk.dart';

/// Assembles text pieces into [StreamChunk]s with stop-sequence detection,
/// guard-length buffering, and periodic heartbeat yields.
///
/// Both the llama.cpp and MLX runtimes produce text pieces differently, but
/// the stream assembly logic (pending buffer, stop detection, flush timing)
/// is identical. This class encapsulates that shared logic.
final class StreamAssembler {
  StreamAssembler({
    required List<String> stopSequences,
    int yieldBoundarySteps = 16,
  }) : _stopSequences = stopSequences,
       _yieldBoundarySteps = yieldBoundarySteps {
    final maxStopLength = _maxStopSequenceLength(stopSequences);
    _guardLength = maxStopLength > 0 ? maxStopLength - 1 : 0;
  }

  final List<String> _stopSequences;
  final int _yieldBoundarySteps;
  late final int _guardLength;

  String _pending = '';
  int _stepsSinceYield = 0;
  int _tokenCountDelta = 0;
  bool _stopped = false;

  /// Whether a stop sequence has been detected.
  bool get stopped => _stopped;

  /// Feeds a text piece produced by the backend.
  ///
  /// Returns a chunk to yield (or null), and sets [stopped] if a stop
  /// sequence was found.
  StreamChunk? addText(String piece) {
    _tokenCountDelta += 1;

    if (piece.isEmpty) {
      return _checkYieldBoundary();
    }

    _pending += piece;

    final stopIndex = _earliestStopIndex(_pending, _stopSequences);
    if (stopIndex != null) {
      _stopped = true;
      final visible = _pending.substring(0, stopIndex);
      _pending = '';
      if (visible.isNotEmpty) {
        final chunk = StreamChunk(
          text: visible,
          tokenCountDelta: _tokenCountDelta,
        );
        _tokenCountDelta = 0;
        return chunk;
      }
      return null;
    }

    var flushLength = _pending.length - _guardLength;
    if (flushLength > 0) {
      // Don't split a UTF-16 surrogate pair at the boundary.
      if (flushLength < _pending.length) {
        final lastUnit = _pending.codeUnitAt(flushLength - 1);
        if (lastUnit >= 0xD800 && lastUnit <= 0xDBFF) {
          flushLength += 1;
        }
      }
      final visible = _pending.substring(0, flushLength);
      _pending = _pending.substring(flushLength);
      if (visible.isNotEmpty) {
        final chunk = StreamChunk(
          text: visible,
          tokenCountDelta: _tokenCountDelta,
        );
        _tokenCountDelta = 0;
        _stepsSinceYield = 0;
        return chunk;
      }
    }

    return _checkYieldBoundary();
  }

  /// Appends raw text to the pending buffer without counting a token.
  ///
  /// Use for text produced by already-counted tokens, e.g. remaining bytes
  /// flushed from a UTF-8 decoder after the generation loop.
  void appendPending(String text) {
    _pending += text;
  }

  /// Records a token that produced no text (control token, empty bytes).
  StreamChunk? addEmptyToken() {
    _tokenCountDelta += 1;
    return _checkYieldBoundary();
  }

  /// Flushes remaining pending text and token count after the loop ends.
  ///
  /// Returns up to two chunks: one for remaining text, one for leftover
  /// token count. Call this after the generation loop completes.
  List<StreamChunk> flush() {
    final chunks = <StreamChunk>[];
    if (_pending.isNotEmpty) {
      final stopIndex = _earliestStopIndex(_pending, _stopSequences);
      final visible = stopIndex == null
          ? _pending
          : _pending.substring(0, stopIndex);
      if (visible.isNotEmpty) {
        chunks.add(
          StreamChunk(text: visible, tokenCountDelta: _tokenCountDelta),
        );
        _tokenCountDelta = 0;
      }
      _pending = '';
    }
    if (_tokenCountDelta > 0) {
      chunks.add(StreamChunk(text: '', tokenCountDelta: _tokenCountDelta));
      _tokenCountDelta = 0;
    }
    return chunks;
  }

  StreamChunk? _checkYieldBoundary() {
    _stepsSinceYield += 1;
    if (_stepsSinceYield >= _yieldBoundarySteps) {
      _stepsSinceYield = 0;
      if (_tokenCountDelta > 0) {
        final chunk = StreamChunk(
          text: '',
          tokenCountDelta: _tokenCountDelta,
        );
        _tokenCountDelta = 0;
        return chunk;
      }
    }
    return null;
  }

  static int _maxStopSequenceLength(List<String> stopSequences) {
    var maxLength = 0;
    for (final stop in stopSequences) {
      if (stop.length > maxLength) {
        maxLength = stop.length;
      }
    }
    return maxLength;
  }

  static int? _earliestStopIndex(String text, List<String> stopSequences) {
    var earliestIndex = -1;
    for (final stop in stopSequences) {
      if (stop.isEmpty) continue;
      final index = text.indexOf(stop);
      if (index == -1) continue;
      if (earliestIndex == -1 || index < earliestIndex) {
        earliestIndex = index;
      }
    }
    return earliestIndex == -1 ? null : earliestIndex;
  }
}
