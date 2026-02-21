@TestOn('mac-os')
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:io';

import 'package:cow_brain/cow_brain.dart';
import 'package:test/test.dart';

void main() {
  final modelPath = Platform.environment['COW_MLX_MODEL_PATH'];
  final summaryModelPath = Platform.environment['COW_MLX_SUMMARY_MODEL_PATH'];
  final libraryPath = Platform.environment['COW_MLX_LIBRARY_PATH'];

  if (modelPath == null || libraryPath == null) {
    stderr.writeln(
      'Skipping MLX e2e tests: '
      'COW_MLX_MODEL_PATH and COW_MLX_LIBRARY_PATH must be set.',
    );
    return;
  }

  // Fall back to same model if summary model not set.
  final effectiveSummaryModelPath = summaryModelPath ?? modelPath;

  const settings = AgentSettings(safetyMarginTokens: 64, maxSteps: 8);
  const summarySetting = AgentSettings(safetyMarginTokens: 32, maxSteps: 2);
  const samplingOptions = SamplingOptions(seed: 42);

  late ModelServer modelServer;
  late CowBrains<String> brains;
  late CowBrain primaryBrain;
  late CowBrain summaryBrain;

  setUp(() async {
    modelServer = await ModelServer.spawn();
    brains = CowBrains<String>(
      libraryPath: libraryPath,
      modelServer: modelServer,
    );

    // Load primary model.
    final primaryLoaded = await brains.loadModel(
      modelPath: modelPath,
      backend: InferenceBackend.mlx,
      libraryPathOverride: libraryPath,
    );

    // Load summary model (may be the same or different).
    final summaryLoaded = await brains.loadModel(
      modelPath: effectiveSummaryModelPath,
      backend: InferenceBackend.mlx,
      libraryPathOverride: libraryPath,
    );

    primaryBrain = brains.create('primary');
    await primaryBrain.init(
      modelHandle: primaryLoaded.modelPointer,
      options: MlxRuntimeOptions(
        modelPath: modelPath,
        libraryPath: libraryPath,
        contextSize: 10000,
        samplingOptions: samplingOptions,
      ),
      profile: ModelProfileId.qwen3,
      tools: const [],
      settings: settings,
      enableReasoning: true,
    );

    summaryBrain = brains.create('summary');
    await summaryBrain.init(
      modelHandle: summaryLoaded.modelPointer,
      options: MlxRuntimeOptions(
        modelPath: effectiveSummaryModelPath,
        libraryPath: libraryPath,
        contextSize: 2048,
        samplingOptions: const SamplingOptions(seed: 99),
      ),
      profile: ModelProfileId.qwen3,
      tools: const [],
      settings: summarySetting,
      enableReasoning: false,
    );
  });

  tearDown(() async {
    await brains.dispose();
  });

  test('single turn with reasoning completes', () async {
    final events = <AgentEvent>[];
    await for (final event in primaryBrain.runTurn(
      userMessage: const Message(role: Role.user, content: 'hi!'),
      settings: settings,
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

  test('second turn completes without crash', () async {
    stdout.writeln('--- Turn 1 ---');
    await for (final event in primaryBrain.runTurn(
      userMessage: const Message(role: Role.user, content: 'hi!'),
      settings: settings,
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
      settings: settings,
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

  // Reproduces the app crash: both brains fire simultaneously.
  // In the app, when a user sends a message:
  //   1. Summary brain immediately starts summarizing the user message
  //   2. Primary brain starts generating reasoning + response
  // Both hit MLX concurrently from separate isolates.
  test(
    'concurrent dual-brain: primary + summary fire simultaneously',
    () async {
      stdout.writeln('--- Dual-brain simultaneous test ---');

      // Fire summary brain on user message (exactly like the app does).
      summaryBrain.reset();
      final summaryFuture = _runSummaryTurn(
        summaryBrain,
        'hi!',
        'You are a concise summarizer. Summarize the user request in one '
            'sentence. Output a single, extremely concise sentence only.',
      );

      // Fire primary brain at the same time.
      final primaryEvents = <AgentEvent>[];
      await for (final event in primaryBrain.runTurn(
        userMessage: const Message(role: Role.user, content: 'hi!'),
        settings: settings,
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
  // The crash is non-deterministic, so we repeat to increase the chance
  // of hitting the race window.
  for (var i = 1; i <= 5; i++) {
    test('concurrent stress run #$i', () async {
      stdout.writeln('--- Stress run #$i ---');

      // Fire summary on user message.
      summaryBrain.reset();
      final summaryFuture = _runSummaryTurn(
        summaryBrain,
        'Tell me about quantum computing',
        'You are a concise summarizer. Summarize the user request in one '
            'sentence. Output a single, extremely concise sentence only.',
      );

      // Primary generates with reasoning.
      final primaryEvents = <AgentEvent>[];
      final reasoningBuffer = StringBuffer();
      Future<String>? reasoningSummaryFuture;

      await for (final event in primaryBrain.runTurn(
        userMessage: const Message(
          role: Role.user,
          content: 'Tell me about quantum computing',
        ),
        settings: settings,
        enableReasoning: true,
      )) {
        primaryEvents.add(event);
        if (event is AgentReasoningDelta) {
          reasoningBuffer.write(event.text);

          // After first summary finishes and we have enough reasoning,
          // fire another summary (like the app does mid-reasoning).
          if (reasoningSummaryFuture == null && reasoningBuffer.length > 40) {
            // Wait for user message summary to finish first.
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

      // Wait for all summaries to complete.
      await summaryFuture;
      if (reasoningSummaryFuture != null) {
        await reasoningSummaryFuture;
      }

      expect(primaryEvents.whereType<AgentTurnFinished>(), hasLength(1));
      stdout.writeln('--- Stress run #$i passed ---');
    });
  }
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
