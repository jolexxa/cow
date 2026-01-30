// Core contracts are evolving; we defer exhaustive API docs for now.
// The one-method parser interface is an intentional contract.
// ignore_for_file: one_member_abstracts, public_member_api_docs

import 'package:cow_brain/src/isolate/models.dart';

final class LlamaParseResult {
  const LlamaParseResult({
    required this.visibleText,
    required this.toolCalls,
    this.reasoningText,
  });

  final String visibleText;
  final String? reasoningText;
  final List<ToolCall> toolCalls;
}

abstract interface class LlamaToolCallParser {
  LlamaParseResult parse(String text);
}
