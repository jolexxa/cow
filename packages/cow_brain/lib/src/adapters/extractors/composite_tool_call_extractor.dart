// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/tool_call_extractor.dart';
import 'package:cow_brain/src/isolate/models.dart';

/// Tries multiple extractors in priority order. First match wins.
final class CompositeToolCallExtractor implements ToolCallExtractor {
  const CompositeToolCallExtractor(this.extractors);

  final List<ToolCallExtractor> extractors;

  @override
  List<ToolCall> extract(String text) {
    for (final extractor in extractors) {
      final calls = extractor.extract(text);
      if (calls.isNotEmpty) return calls;
    }
    return const [];
  }
}
