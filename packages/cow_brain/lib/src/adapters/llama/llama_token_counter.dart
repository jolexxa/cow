// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/llama/llama_prompt_formatter.dart';
import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/isolate/models.dart';

typedef LlamaPromptTokenCounter =
    int Function(
      String prompt, {
      required bool addBos,
    });

/// Token counter that counts tokens on the fully formatted prompt.
final class LlamaTokenCounter implements TokenCounter {
  const LlamaTokenCounter({
    required LlamaPromptFormatter formatter,
    required LlamaPromptTokenCounter tokenCounter,
  }) : _formatter = formatter,
       _tokenCounter = tokenCounter;

  final LlamaPromptFormatter _formatter;
  final LlamaPromptTokenCounter _tokenCounter;

  @override
  int countPromptTokens({
    required List<Message> messages,
    required List<ToolDefinition> tools,
    required bool systemApplied,
  }) {
    // Token estimation assumes reasoning is enabled for consistent sizing.
    final prompt = _formatter.format(
      messages: messages,
      tools: tools,
      systemApplied: systemApplied,
      enableReasoning: true,
    );
    return _tokenCounter(prompt, addBos: _formatter.addBos);
  }
}
