@TestOn('mac-os || linux')
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:cow_brain/cow_brain.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  silenceNativeStderr();
  final paths = TestPaths.resolve();

  if (paths.llamaUnavailable) {
    stderr.writeln('Skipping: llama model or library not found.');
    return;
  }

  late ModelServer modelServer;
  late CowBrains<String> brains;
  late CowBrain brain;

  setUp(() async {
    modelServer = await ModelServer.spawn();
    brains = CowBrains<String>(
      libraryPath: paths.llamaLibraryPath,
      modelServer: modelServer,
    );

    final loaded = await brains.loadModel(
      modelPath: paths.llamaModelPath,
      modelOptions: const LlamaModelOptions(nGpuLayers: -1, useMmap: true),
      libraryPathOverride: paths.llamaLibraryPath,
    );

    brain = brains.create('llama');
    await brain.init(
      modelHandle: loaded.modelPointer,
      options: LlamaCppRuntimeOptions(
        modelPath: paths.llamaModelPath,
        libraryPath: paths.llamaLibraryPath,
        contextOptions: const LlamaContextOptions(
          contextSize: 8192,
          nBatch: 512,
          nThreads: 4,
          nThreadsBatch: 4,
          useFlashAttn: true,
        ),
        modelOptions: const LlamaModelOptions(
          nGpuLayers: -1,
          useMmap: true,
        ),
        samplingOptions: defaultSamplingOptions,
      ),
      profile: ModelProfileId.qwen3,
      tools: const [
        ToolDefinition(
          name: 'date_time',
          description: 'Returns the current date/time in ISO 8601 format.',
          parameters: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
            'required': <String>[],
          },
        ),
      ],
      settings: defaultSettings,
      enableReasoning: true,
      systemPrompt: 'You are a helpful assistant.',
    );
  });

  tearDown(() async {
    await brains.dispose();
  });

  // Verifies tool definitions survive 6 turns with reasoning toggling every
  // turn on the llama.cpp backend. Mirrors the MLX version of this test.
  test(
    'tool definitions persist across 6 turns with reasoning toggling',
    () async {
      const turns = [
        (msg: "What's the capital of France?", reasoning: true),
        (msg: 'Name three primary colors.', reasoning: false),
        (msg: "What's 7 times 8?", reasoning: true),
        (msg: 'Who wrote Romeo and Juliet?', reasoning: false),
        (msg: "What's the boiling point of water in Celsius?", reasoning: true),
        (
          msg:
              'What is the current date and time? '
              'Use the date_time tool to find out.',
          reasoning: false,
        ),
      ];

      for (var i = 0; i < turns.length; i++) {
        final turn = turns[i];
        final turnNum = i + 1;
        final isLastTurn = turnNum == turns.length;

        stdout.writeln(
          '--- Turn $turnNum (reasoning=${turn.reasoning}) ---',
        );

        final events = <AgentEvent>[];
        await for (final event in brain.runTurn(
          userMessage: Message(role: Role.user, content: turn.msg),
          settings: defaultSettings,
          enableReasoning: turn.reasoning,
        )) {
          events.add(event);
          if (event is AgentTextDelta) stdout.write(event.text);
          if (event is AgentReasoningDelta) stderr.write(event.text);
          if (event is AgentToolCalls) {
            for (final call in event.calls) {
              brain.sendToolResult(
                turnId: event.turnId,
                toolResult: ToolResult(
                  toolCallId: call.id,
                  name: call.name,
                  content: '2026-02-24T12:00:00Z',
                ),
              );
            }
          }
        }
        stdout.writeln();

        expect(
          events.whereType<AgentTurnFinished>(),
          hasLength(1),
          reason:
              'Turn $turnNum should complete with exactly one '
              'AgentTurnFinished event.',
        );

        if (isLastTurn) {
          final toolCalls = events.whereType<AgentToolCalls>();
          stdout.writeln('Turn $turnNum tool calls: ${toolCalls.length}');
          expect(
            toolCalls,
            isNotEmpty,
            reason:
                'Turn $turnNum should call date_time, but no tool calls '
                'were emitted. Tool definitions were lost after reasoning '
                'toggling across $turnNum turns.',
          );
        }
      }

      stdout.writeln('--- All 6 turns passed ---');
    },
  );
}
