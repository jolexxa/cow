import 'dart:async';

import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:cow_brain/src/core/model_output.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

void main() {
  group('LlamaAdapter', () {
    const config = LlmConfig(
      requiresReset: false,
      reusePrefixMessageCount: 0,
    );

    test('parses runtime output into model outputs', () async {
      final runtime = FakeLlamaRuntime(
        outputChunks: const [
          '<think>Quiet plan.</think>',
          'Working...<tool_call>{"id":"1","name":"search","arguments":{"query":"cows"}}</tool_call>',
        ],
      );
      final adapter = LlamaAdapter(
        runtime: runtime,
        profile: LlamaModelProfile(
          formatter: const Qwen3PromptFormatter(),
          streamParser: UniversalStreamParser(
            config: StreamParserConfig(
              toolCallExtractor: const JsonToolCallExtractor(),
              tags: StreamTokenizer.defaultTags,
              supportsReasoning: true,
              enableFallbackToolParsing: false,
            ),
          ),
        ),
      );

      final outputs = await adapter
          .next(
            messages: const [
              Message(role: Role.user, content: 'Find cow facts.'),
            ],
            tools: const [
              ToolDefinition(
                name: 'search',
                description: 'Search the web',
                parameters: {'type': 'object'},
              ),
            ],
            systemApplied: false,
            enableReasoning: true,
            config: config,
          )
          .toList();

      expect(runtime.lastPrompt, contains('<tools>'));
      expect(outputs, hasLength(4));
      expect(outputs[0], isA<OutputReasoningDelta>());
      expect((outputs[0] as OutputReasoningDelta).text, 'Quiet plan.');
      expect(outputs[1], isA<OutputTextDelta>());
      expect((outputs[1] as OutputTextDelta).text, contains('Working...'));
      expect(outputs[2], isA<OutputToolCalls>());
      expect((outputs[2] as OutputToolCalls).calls.single.name, 'search');
      expect(outputs[3], isA<OutputStepFinished>());
      expect((outputs[3] as OutputStepFinished).reason, FinishReason.stop);
    });

    test('exposes a formatter-aware token counter', () {
      final runtime = FakeLlamaRuntime(outputChunks: const []);
      final adapter = LlamaAdapter(
        runtime: runtime,
        profile: LlamaModelProfile(
          formatter: const Qwen3PromptFormatter(),
          streamParser: UniversalStreamParser(
            config: StreamParserConfig(
              toolCallExtractor: const JsonToolCallExtractor(),
              tags: StreamTokenizer.defaultTags,
              supportsReasoning: true,
              enableFallbackToolParsing: false,
            ),
          ),
        ),
      );

      final tokens = adapter.tokenCounter.countPromptTokens(
        messages: const [Message(role: Role.user, content: 'Hello')],
        tools: const [],
        systemApplied: false,
      );

      expect(tokens, greaterThan(0));
    });

    test('forwards formatter settings to the runtime', () async {
      final runtime = FakeLlamaRuntime(outputChunks: const ['Hi']);
      final adapter = LlamaAdapter(
        runtime: runtime,
        profile: LlamaModelProfile(
          formatter: const Qwen3PromptFormatter(),
          streamParser: UniversalStreamParser(
            config: StreamParserConfig(
              toolCallExtractor: const JsonToolCallExtractor(),
              tags: StreamTokenizer.defaultTags,
              supportsReasoning: true,
              enableFallbackToolParsing: false,
            ),
          ),
        ),
      );

      await adapter
          .next(
            messages: const [
              Message(role: Role.user, content: 'Hello'),
            ],
            tools: const [],
            systemApplied: false,
            enableReasoning: true,
            config: config,
          )
          .toList();

      expect(runtime.lastAddBos, isTrue);
      expect(
        runtime.lastStopSequences,
        const Qwen3PromptFormatter().stopSequences,
      );
    });
  });
}

final class FakeLlamaRuntime implements LlamaRuntime {
  FakeLlamaRuntime({required this.outputChunks});

  final List<String> outputChunks;
  String lastPrompt = '';
  bool lastAddBos = false;
  List<String> lastStopSequences = const [];

  @override
  int countTokens(String prompt, {required bool addBos}) {
    lastPrompt = prompt;
    lastAddBos = addBos;
    return prompt.length + (addBos ? 1 : 0);
  }

  @override
  Stream<LlamaStreamChunk> generate({
    required String prompt,
    required List<String> stopSequences,
    required bool addBos,
    required bool requiresReset,
    required int reusePrefixMessageCount,
  }) async* {
    lastPrompt = prompt;
    lastAddBos = addBos;
    lastStopSequences = stopSequences;
    for (final chunk in outputChunks) {
      yield LlamaStreamChunk(text: chunk, tokenCountDelta: 0);
    }
  }
}
