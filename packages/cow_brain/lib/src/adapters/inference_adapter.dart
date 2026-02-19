// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/local_token_counter.dart';
import 'package:cow_brain/src/adapters/prompt_formatter.dart';
import 'package:cow_brain/src/adapters/stream_chunk.dart';
import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/core/llm_adapter.dart';
import 'package:cow_brain/src/core/model_output.dart';
import 'package:cow_brain/src/isolate/models.dart';

abstract interface class InferenceRuntime {
  int countTokens(
    String prompt, {
    required bool addBos,
  });

  Stream<StreamChunk> generate({
    required String prompt,
    required List<String> stopSequences,
    required bool addBos,
    required bool requiresReset,
    required int reusePrefixMessageCount,
  });
}

/// Thin llama-based adapter that defers model specifics to a profile.
final class InferenceAdapter implements LlmAdapter {
  InferenceAdapter({
    required InferenceRuntime runtime,
    required this.profile,
  }) : _runtime = runtime,
       tokenCounter = LocalTokenCounter(
         formatter: profile.formatter,
         tokenCounter: runtime.countTokens,
       );

  final InferenceRuntime _runtime;

  /// The resolved model profile used by this adapter.
  final ModelProfile profile;

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
    final prompt = profile.formatter.format(
      messages: messages,
      tools: tools,
      systemApplied: systemApplied,
      enableReasoning: enableReasoning,
    );
    yield* profile.streamParser.parse(
      _runtime.generate(
        prompt: prompt,
        stopSequences: profile.formatter.stopSequences,
        addBos: profile.formatter.addBos,
        requiresReset: config.requiresReset,
        reusePrefixMessageCount: config.reusePrefixMessageCount,
      ),
    );
  }
}
