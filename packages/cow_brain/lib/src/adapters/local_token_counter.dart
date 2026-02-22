// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/prompt_formatter.dart';
import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/isolate/models.dart';

typedef PromptTokenCounter =
    int Function(
      String prompt, {
      required bool addBos,
    });

/// Token counter that counts tokens on the fully formatted prompt.
final class LocalTokenCounter implements TokenCounter {
  const LocalTokenCounter({
    required PromptFormatter formatter,
    required PromptTokenCounter tokenCounter,
  }) : _formatter = formatter,
       _tokenCounter = tokenCounter;

  final PromptFormatter _formatter;
  final PromptTokenCounter _tokenCounter;

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
