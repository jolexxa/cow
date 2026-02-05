// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/llama/llama_stream_parser.dart';
import 'package:cow_brain/src/isolate/models.dart';

extension RoleName on Role {
  String get roleName => switch (this) {
    Role.system => 'system',
    Role.user => 'user',
    Role.assistant => 'assistant',
    Role.tool => 'tool',
  };
}

abstract interface class LlamaPromptFormatter {
  String format({
    required List<Message> messages,
    required List<ToolDefinition> tools,
    required bool systemApplied,
    required bool enableReasoning,
  });

  List<String> get stopSequences;
  bool get addBos;
}

final class LlamaModelProfile {
  const LlamaModelProfile({
    required this.formatter,
    required this.streamParser,
  });

  final LlamaPromptFormatter formatter;
  final LlamaStreamParser streamParser;
}
