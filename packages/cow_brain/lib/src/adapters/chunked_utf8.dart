// Shared UTF-8 chunked decoding helpers used by both runtimes.
// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:meta/meta.dart';

/// Drains all accumulated chunks into a single string and clears the list.
String drainDecodedChunks(List<String> decodedChunks) {
  final piece = decodedChunks.length == 1
      ? decodedChunks.removeAt(0)
      : decodedChunks.join();
  if (decodedChunks.isNotEmpty) {
    decodedChunks.clear();
  }
  return piece;
}

/// A [StringSink] that appends each write to a list of chunks.
///
/// Used with [Utf8Decoder.startChunkedConversion] to collect decoded text
/// pieces without eagerly concatenating them.
@visibleForTesting
final class ChunkedStringSink implements StringSink {
  ChunkedStringSink(this._chunks);

  final List<String> _chunks;

  @override
  void write(Object? obj) {
    if (obj == null) return;
    _chunks.add(obj.toString());
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    var first = true;
    for (final obj in objects) {
      if (!first && separator.isNotEmpty) _chunks.add(separator);
      first = false;
      if (obj == null) continue;
      _chunks.add(obj.toString());
    }
  }

  @override
  void writeCharCode(int charCode) {
    _chunks.add(String.fromCharCode(charCode));
  }

  @override
  void writeln([Object? obj = '']) {
    if (obj != null && obj.toString().isNotEmpty) _chunks.add(obj.toString());
    _chunks.add('\n');
  }
}
