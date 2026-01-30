// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/llama/llama_prompt_formatter.dart';
import 'package:cow_brain/src/adapters/llama/llama_stream_chunk.dart';
import 'package:cow_brain/src/adapters/llama/llama_token_counter.dart';
import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/core/llm_adapter.dart';
import 'package:cow_brain/src/core/model_output.dart';
import 'package:cow_brain/src/isolate/models.dart';

abstract interface class LlamaRuntime {
  int countTokens(
    String prompt, {
    required bool addBos,
  });

  Stream<LlamaStreamChunk> generate({
    required String prompt,
    required List<String> stopSequences,
    required bool addBos,
    required bool requiresReset,
    required int reusePrefixMessageCount,
  });
}

/// Thin llama-based adapter that defers model specifics to a profile.
final class LlamaAdapter implements LlmAdapter {
  LlamaAdapter({
    required LlamaRuntime runtime,
    required LlamaModelProfile profile,
  }) : _runtime = runtime,
       _profile = profile,
       tokenCounter = LlamaTokenCounter(
         formatter: profile.formatter,
         tokenCounter: runtime.countTokens,
       );

  final LlamaRuntime _runtime;
  final LlamaModelProfile _profile;

  /// Exposes a formatter-aware token counter for the context manager.
  final TokenCounter tokenCounter;

  @override
  Stream<ModelOutput> next({
    required List<Message> messages,
    required List<ToolDefinition> tools,
    required bool systemApplied,
    required bool enableReasoning,
    required LlmConfig config,
  }) async* {
    final prompt = _profile.formatter.format(
      messages: messages,
      tools: tools,
      systemApplied: systemApplied,
      enableReasoning: enableReasoning,
    );
    yield* _profile.streamParser.parse(
      _runtime.generate(
        prompt: prompt,
        stopSequences: _profile.formatter.stopSequences,
        addBos: _profile.formatter.addBos,
        requiresReset: config.requiresReset,
        reusePrefixMessageCount: config.reusePrefixMessageCount,
      ),
    );
  }
}
