// Core contracts are evolving; we defer exhaustive API docs for now.
// The one-method extractor interface is an intentional contract.
// ignore_for_file: one_member_abstracts, public_member_api_docs

import 'package:cow_brain/src/isolate/models.dart';

/// Extracts tool calls from raw text content.
///
/// Reasoning/visible-text separation is handled by the stream tokenizer via
/// tags.
abstract interface class ToolCallExtractor {
  List<ToolCall> extract(String text);
}
