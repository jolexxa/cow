// Core contracts are evolving; we defer exhaustive API docs for now.

/// Token types emitted by the stream tokenizer.
enum StreamTokenType {
  /// Normal text content.
  text,

  /// Opening `<think>` tag.
  thinkStart,

  /// Closing `</think>` tag.
  thinkEnd,

  /// Opening `<tool_call>` tag.
  toolStart,

  /// Closing `</tool_call>` tag.
  toolEnd,
}

/// A token emitted by the stream tokenizer.
typedef StreamToken = ({StreamTokenType type, String? text});

/// Tokenizes a stream of string chunks into a stream of typed tokens.
///
/// Handles tag boundaries across chunk boundaries by buffering and using
/// a guard length to avoid flushing partial tags.
final class StreamTokenizer {
  /// Tokenizes a stream of string chunks into typed tokens.
  Stream<StreamToken> tokenize(Stream<String> chunks) async* {
    final buffer = StringBuffer();

    await for (final chunk in chunks) {
      buffer.write(chunk);

      while (buffer.isNotEmpty) {
        final bufferStr = buffer.toString();
        final tag = _findEarliestTag(bufferStr);

        if (tag == null) {
          // No complete tag found - flush safe portion, keep guard.
          final (flush, remainder) = _flushWithGuard(bufferStr, _maxTagLength);
          if (flush.isNotEmpty) {
            yield (type: StreamTokenType.text, text: flush);
          }
          buffer
            ..clear()
            ..write(remainder);
          break;
        }

        // Emit text before tag.
        if (tag.index > 0) {
          final textBefore = bufferStr.substring(0, tag.index);
          yield (type: StreamTokenType.text, text: textBefore);
        }

        // Emit tag token.
        yield (type: tag.type, text: null);
        buffer
          ..clear()
          ..write(bufferStr.substring(tag.index + tag.length));
      }
    }

    // Flush remaining buffer.
    if (buffer.isNotEmpty) {
      yield (type: StreamTokenType.text, text: buffer.toString());
    }
  }

  static const _tags = <(String, StreamTokenType)>[
    ('<think>', StreamTokenType.thinkStart),
    ('</think>', StreamTokenType.thinkEnd),
    ('<tool_call>', StreamTokenType.toolStart),
    ('</tool_call>', StreamTokenType.toolEnd),
  ];

  static final int _maxTagLength = _tags
      .map((t) => t.$1.length)
      .reduce(
        (a, b) => a > b ? a : b,
      );

  static ({int index, int length, StreamTokenType type})? _findEarliestTag(
    String buffer,
  ) {
    ({int index, int length, StreamTokenType type})? earliest;

    for (final (tag, type) in _tags) {
      final index = buffer.indexOf(tag);
      if (index == -1) continue;
      if (earliest == null || index < earliest.index) {
        earliest = (index: index, length: tag.length, type: type);
      }
    }

    return earliest;
  }

  static (String flush, String remainder) _flushWithGuard(
    String buffer,
    int guardLength,
  ) {
    if (guardLength <= 0) {
      return (buffer, '');
    }
    final effectiveGuard = guardLength - 1;
    if (buffer.length <= effectiveGuard) {
      return ('', buffer);
    }
    final flushLength = buffer.length - effectiveGuard;
    return (buffer.substring(0, flushLength), buffer.substring(flushLength));
  }
}
