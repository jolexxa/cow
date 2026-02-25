@TestOn('mac-os')
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:cow_brain/cow_brain.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  silenceNativeStderr();
  final paths = TestPaths.resolve();

  if (paths.mlxUnavailable) {
    stderr.writeln('Skipping: MLX model or library not found.');
    return;
  }

  final effectiveSummaryModelPath = paths.mlxSummaryUnavailable
      ? paths.mlxModelPath
      : paths.mlxSummaryModelPath;

  const summarySetting = AgentSettings(safetyMarginTokens: 32, maxSteps: 2);

  late ModelServer modelServer;
  late CowBrains<String> brains;
  late CowBrain primaryBrain;
  late CowBrain summaryBrain;

  setUp(() async {
    modelServer = await ModelServer.spawn();
    brains = CowBrains<String>(
      libraryPath: paths.mlxLibraryPath,
      modelServer: modelServer,
    );

    // Load primary model.
    final primaryLoaded = await brains.loadModel(
      modelPath: paths.mlxModelPath,
      backend: InferenceBackend.mlx,
      libraryPathOverride: paths.mlxLibraryPath,
    );

    // Load summary model (may be the same or different).
    final summaryLoaded = await brains.loadModel(
      modelPath: effectiveSummaryModelPath,
      backend: InferenceBackend.mlx,
      libraryPathOverride: paths.mlxLibraryPath,
    );

    primaryBrain = brains.create('primary');
    await primaryBrain.init(
      modelHandle: primaryLoaded.modelPointer,
      options: MlxRuntimeOptions(
        modelPath: paths.mlxModelPath,
        libraryPath: paths.mlxLibraryPath,
        contextSize: 10000,
        samplingOptions: defaultSamplingOptions,
      ),
      profile: ModelProfileId.qwen3,
      tools: const [],
      settings: defaultSettings,
      enableReasoning: true,
      systemPrompt: 'You are a helpful assistant.',
    );

    summaryBrain = brains.create('summary');
    await summaryBrain.init(
      modelHandle: summaryLoaded.modelPointer,
      options: MlxRuntimeOptions(
        modelPath: effectiveSummaryModelPath,
        libraryPath: paths.mlxLibraryPath,
        contextSize: 2048,
        samplingOptions: const SamplingOptions(seed: 99),
      ),
      profile: ModelProfileId.qwen3,
      tools: const [],
      settings: summarySetting,
      enableReasoning: false,
      systemPrompt: 'You are a summarization assistant.',
    );
  });

  tearDown(() async {
    await brains.dispose();
  });

  test('single turn with reasoning completes', () async {
    final events = <AgentEvent>[];
    await for (final event in primaryBrain.runTurn(
      userMessage: const Message(role: Role.user, content: 'hi!'),
      settings: defaultSettings,
      enableReasoning: true,
    )) {
      events.add(event);
      if (event is AgentTextDelta) {
        stdout.write(event.text);
      } else if (event is AgentReasoningDelta) {
        stderr.write(event.text);
      }
    }
    stdout.writeln();
    expect(events.whereType<AgentTurnFinished>(), hasLength(1));
  });

  test('reasoning output is classified as reasoning, not text', () async {
    final reasoningBuf = StringBuffer();
    final textBuf = StringBuffer();
    final events = <AgentEvent>[];

    await for (final event in primaryBrain.runTurn(
      userMessage: const Message(
        role: Role.user,
        content: 'What is 2+2? Think step by step.',
      ),
      settings: defaultSettings,
      enableReasoning: true,
    )) {
      events.add(event);
      if (event is AgentReasoningDelta) {
        reasoningBuf.write(event.text);
      } else if (event is AgentTextDelta) {
        textBuf.write(event.text);
      }
    }

    final reasoning = reasoningBuf.toString();
    final text = textBuf.toString();

    stdout
      ..writeln('--- Reasoning (${reasoning.length} chars) ---')
      ..writeln(reasoning.isEmpty ? '(empty)' : reasoning)
      ..writeln('--- Text (${text.length} chars) ---')
      ..writeln(text.isEmpty ? '(empty)' : text)
      ..writeln('---');

    expect(
      reasoning,
      isNotEmpty,
      reason:
          'Expected reasoning output (AgentReasoningDelta events), '
          'but got none. Full text output was: $text',
    );

    expect(reasoning, isNot(contains('<think>')));
    expect(reasoning, isNot(contains('</think>')));
    expect(text, isNot(contains('<think>')));
    expect(text, isNot(contains('</think>')));

    expect(events.whereType<AgentTurnFinished>(), hasLength(1));
  });

  test('second turn completes without crash', () async {
    stdout.writeln('--- Turn 1 ---');
    await for (final event in primaryBrain.runTurn(
      userMessage: const Message(role: Role.user, content: 'hi!'),
      settings: defaultSettings,
      enableReasoning: true,
    )) {
      if (event is AgentTextDelta) stdout.write(event.text);
    }
    stdout
      ..writeln()
      ..writeln('--- Turn 2 ---');
    final events = <AgentEvent>[];
    await for (final event in primaryBrain.runTurn(
      userMessage: const Message(
        role: Role.user,
        content: 'what is 2+2?',
      ),
      settings: defaultSettings,
      enableReasoning: true,
    )) {
      events.add(event);
      if (event is AgentTextDelta) stdout.write(event.text);
    }
    stdout
      ..writeln()
      ..writeln('Turn 2 events: ${events.length}');
    expect(events.whereType<AgentTurnFinished>(), hasLength(1));
  });

  test('tool definitions survive across turns', () async {
    final toolBrain = brains.create('tool-test');
    final loaded = await brains.loadModel(
      modelPath: paths.mlxModelPath,
      backend: InferenceBackend.mlx,
      libraryPathOverride: paths.mlxLibraryPath,
    );
    await toolBrain.init(
      modelHandle: loaded.modelPointer,
      options: MlxRuntimeOptions(
        modelPath: paths.mlxModelPath,
        libraryPath: paths.mlxLibraryPath,
        contextSize: 10000,
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

    // Turn 1: warm-up.
    stdout.writeln('--- Tool test: Turn 1 ---');
    await for (final event in toolBrain.runTurn(
      userMessage: const Message(role: Role.user, content: 'hi!'),
      settings: defaultSettings,
      enableReasoning: true,
    )) {
      if (event is AgentTextDelta) stdout.write(event.text);
    }
    // Turn 2: ask for the time — model should call the date_time tool.
    stdout
      ..writeln()
      ..writeln('--- Tool test: Turn 2 ---');
    final events = <AgentEvent>[];
    await for (final event in toolBrain.runTurn(
      userMessage: const Message(
        role: Role.user,
        content:
            'What is the current date and time? '
            'Use the date_time tool to find out.',
      ),
      settings: defaultSettings,
      enableReasoning: true,
    )) {
      events.add(event);
      if (event is AgentTextDelta) stdout.write(event.text);
      if (event is AgentReasoningDelta) stderr.write(event.text);
      if (event is AgentToolCalls) {
        for (final call in event.calls) {
          toolBrain.sendToolResult(
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

    final toolCalls = events.whereType<AgentToolCalls>();
    stdout.writeln('Tool calls emitted: ${toolCalls.length}');

    expect(
      toolCalls,
      isNotEmpty,
      reason:
          'Expected the model to call date_time on turn 2, but it did not. '
          'This indicates tool definitions were lost after turn 1 '
          '(systemApplied=true causes the formatter to omit tools from '
          'the prompt, and MLX has no KV cache prefix reuse).',
    );
  });

  test(
    'tool definitions persist across 6 turns with reasoning toggling',
    () async {
      final toolBrain = brains.create('tool-6turn');
      final loaded = await brains.loadModel(
        modelPath: paths.mlxModelPath,
        backend: InferenceBackend.mlx,
        libraryPathOverride: paths.mlxLibraryPath,
      );
      await toolBrain.init(
        modelHandle: loaded.modelPointer,
        options: MlxRuntimeOptions(
          modelPath: paths.mlxModelPath,
          libraryPath: paths.mlxLibraryPath,
          contextSize: 10000,
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

      await _run6TurnToolPersistence(toolBrain);
    },
  );

  // Reproduces the app crash: both brains fire simultaneously.
  test(
    'concurrent dual-brain: primary + summary fire simultaneously',
    () async {
      stdout.writeln('--- Dual-brain simultaneous test ---');

      summaryBrain.reset();
      final summaryFuture = _runSummaryTurn(
        summaryBrain,
        'hi!',
        'You are a concise summarizer. Summarize the user request in one '
            'sentence. Output a single, extremely concise sentence only.',
      );

      final primaryEvents = <AgentEvent>[];
      await for (final event in primaryBrain.runTurn(
        userMessage: const Message(role: Role.user, content: 'hi!'),
        settings: defaultSettings,
        enableReasoning: true,
      )) {
        primaryEvents.add(event);
        if (event is AgentReasoningDelta) {
          stderr.write(event.text);
        }
        if (event is AgentTextDelta) {
          stdout.write(event.text);
        }
      }

      stdout.writeln('\n--- Primary done, waiting for summary ---');
      final summary = await summaryFuture;
      stdout.writeln('Summary: $summary');

      expect(primaryEvents.whereType<AgentTurnFinished>(), hasLength(1));
      expect(summary, isNotEmpty);
      stdout.writeln('--- Dual-brain test passed ---');
    },
  );

  // Stress test: run the simultaneous dual-brain scenario multiple times.
  for (var i = 1; i <= 5; i++) {
    test('concurrent stress run #$i', () async {
      stdout.writeln('--- Stress run #$i ---');

      summaryBrain.reset();
      final summaryFuture = _runSummaryTurn(
        summaryBrain,
        'Tell me about quantum computing',
        'You are a concise summarizer. Summarize the user request in one '
            'sentence. Output a single, extremely concise sentence only.',
      );

      final primaryEvents = <AgentEvent>[];
      final reasoningBuffer = StringBuffer();
      Future<String>? reasoningSummaryFuture;

      await for (final event in primaryBrain.runTurn(
        userMessage: const Message(
          role: Role.user,
          content: 'Tell me about quantum computing',
        ),
        settings: defaultSettings,
        enableReasoning: true,
      )) {
        primaryEvents.add(event);
        if (event is AgentReasoningDelta) {
          reasoningBuffer.write(event.text);

          if (reasoningSummaryFuture == null && reasoningBuffer.length > 40) {
            await summaryFuture;
            summaryBrain.reset();
            reasoningSummaryFuture = _runSummaryTurn(
              summaryBrain,
              reasoningBuffer.toString(),
              'You are a concise summarizer. Summarize the following reasoning '
              'so far in one sentence.',
            );
          }
        }
      }

      await summaryFuture;
      if (reasoningSummaryFuture != null) {
        await reasoningSummaryFuture;
      }

      expect(primaryEvents.whereType<AgentTurnFinished>(), hasLength(1));
      stdout.writeln('--- Stress run #$i passed ---');
    });
  }
}

/// Runs 6 turns with reasoning toggling, mundane questions for turns 1-5,
/// and a date_time tool call on turn 6. Asserts tool call is emitted.
Future<void> _run6TurnToolPersistence(CowBrain brain) async {
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
}

/// Runs a full summary turn and returns the accumulated text.
Future<String> _runSummaryTurn(
  CowBrain brain,
  String text,
  String prompt,
) async {
  final buffer = StringBuffer();
  await for (final event in brain.runTurn(
    userMessage: Message(role: Role.user, content: '$prompt\n\n$text'),
    settings: const AgentSettings(safetyMarginTokens: 32, maxSteps: 2),
    enableReasoning: false,
  )) {
    if (event is AgentTextDelta) {
      buffer.write(event.text);
    }
  }
  return buffer.toString();
}
