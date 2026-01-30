// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: one_member_abstracts, public_member_api_docs

import 'package:cow_brain/src/core/model_output.dart';
import 'package:cow_brain/src/isolate/models.dart';

abstract interface class LlmAdapter {
  Stream<ModelOutput> next({
    required List<Message> messages,
    required List<ToolDefinition> tools,
    required bool systemApplied,
    required bool enableReasoning,
    required LlmConfig config,
  });
}
