// Not required for test files
import 'dart:isolate';

import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:cow_brain/src/cow_brain_api.dart';
import 'package:cow_brain/src/isolate/brain_harness.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

import '../fixtures/fake_bindings.dart';

void _fakeBrainIsolate(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is! Map) {
      return;
    }
    final request = BrainRequest.fromJson(Map<String, Object?>.from(message));
    switch (request.type) {
      case BrainRequestType.init:
        sendPort.send(const AgentReady().toJson());
      case BrainRequestType.runTurn:
        sendPort.send(
          const AgentTurnFinished(
            turnId: 'turn-1',
            step: 1,
            finishReason: FinishReason.stop,
          ).toJson(),
        );
      case BrainRequestType.toolResult:
      case BrainRequestType.cancel:
      case BrainRequestType.reset:
      case BrainRequestType.dispose:
        return;
    }
  });
}

void main() {
  group('CowBrain', () {
    setUp(() {
      LlamaClient.openBindings = ({required String libraryPath}) =>
          FakeLlamaBindings();
    });

    tearDown(() {
      LlamaClient.openBindings = LlamaBindingsLoader.open;
    });

    test('can be instantiated', () {
      expect(CowBrain(libraryPath: '/tmp/libllama.so'), isNotNull);
    });

    test('forwards calls to the harness', () async {
      final harness = BrainHarness(entrypoint: _fakeBrainIsolate);
      final brain = CowBrain(
        libraryPath: '/tmp/libllama.so',
        harness: harness,
      );

      await brain.init(
        runtimeOptions: _runtimeOptions(),
        profile: LlamaProfileId.qwen3,
        tools: const <ToolDefinition>[],
        settings: _settings(),
        enableReasoning: true,
      );

      final events = await brain
          .runTurn(
            userMessage: const Message(role: Role.user, content: 'hello'),
            settings: _settings(),
            enableReasoning: true,
          )
          .toList();
      expect(events.last, isA<AgentTurnFinished>());

      brain
        ..sendToolResult(
          turnId: 'turn-1',
          toolResult: const ToolResult(
            toolCallId: 'call-1',
            name: 'search',
            content: 'ok',
          ),
        )
        ..cancel('turn-1')
        ..reset();

      await brain.dispose();
    });
  });

  group('CowBrains', () {
    setUp(() {
      LlamaClient.openBindings = ({required String libraryPath}) =>
          FakeLlamaBindings();
    });

    tearDown(() {
      LlamaClient.openBindings = LlamaBindingsLoader.open;
    });

    test('creates, reuses, removes, and disposes brains', () async {
      final brains = CowBrains<String>(libraryPath: '/tmp/libllama.so');
      final harnessA = BrainHarness(entrypoint: _fakeBrainIsolate);
      final harnessB = BrainHarness(entrypoint: _fakeBrainIsolate);

      final brainA = brains.create('a', harness: harnessA);
      final brainAAgain = brains.create('a');
      final brainB = brains.create('b', harness: harnessB);

      expect(identical(brainA, brainAAgain), isTrue);
      expect(brains.keys.toSet(), {'a', 'b'});
      expect(brains.values.length, 2);

      final brainC = brains.create('c');
      expect(brains['c'], same(brainC));
      expect(brains.keys.toSet(), {'a', 'b', 'c'});
      expect(brains.values.length, 3);

      await brainA.init(
        runtimeOptions: _runtimeOptions(),
        profile: LlamaProfileId.qwen3,
        tools: const <ToolDefinition>[],
        settings: _settings(),
        enableReasoning: true,
      );
      await brainB.init(
        runtimeOptions: _runtimeOptions(),
        profile: LlamaProfileId.qwen3,
        tools: const <ToolDefinition>[],
        settings: _settings(),
        enableReasoning: true,
      );

      await brains.remove('a');
      expect(brains['a'], isNull);

      await brains.dispose();
      expect(brains.keys, isEmpty);
    });
  });
}

LlamaRuntimeOptions _runtimeOptions() {
  return const LlamaRuntimeOptions(
    modelPath: '/tmp/model.gguf',
    libraryPath: '/tmp/libllama.so',
    contextOptions: LlamaContextOptions(
      contextSize: 2048,
      nBatch: 64,
      nThreads: 8,
      nThreadsBatch: 8,
    ),
  );
}

AgentSettings _settings() {
  return const AgentSettings(
    safetyMarginTokens: 64,
    maxSteps: 8,
  );
}
