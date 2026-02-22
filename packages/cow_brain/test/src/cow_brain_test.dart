// Not required for test files
import 'dart:isolate';

import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:cow_brain/src/cow_brain.dart';
import 'package:cow_brain/src/isolate/brain_harness.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/model_server/model_server.dart';
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

void _fakeModelServerIsolate(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  var modelCounter = 1;

  receivePort.listen((message) {
    if (message is! Map) return;
    final request = ModelServerRequest.fromJson(
      Map<String, Object?>.from(message),
    );

    switch (request) {
      case LoadModelRequest():
        sendPort.send(
          ModelLoadedResponse(
            modelPath: request.modelPath,
            modelPointer: modelCounter++,
          ).toJson(),
        );
      case UnloadModelRequest():
        sendPort.send(
          ModelUnloadedResponse(modelPath: request.modelPath).toJson(),
        );
      case DisposeModelServerRequest():
        receivePort.close();
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
      expect(CowBrain(), isNotNull);
    });

    test('forwards calls to the harness', () async {
      final harness = BrainHarness(entrypoint: _fakeBrainIsolate);
      final brain = CowBrain(harness: harness);

      await brain.init(
        modelHandle: 1,
        options: _runtimeOptions(),
        profile: ModelProfileId.qwen3,
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
      modelServerIsolateEntryOverride = _fakeModelServerIsolate;
    });

    tearDown(() {
      LlamaClient.openBindings = LlamaBindingsLoader.open;
      modelServerIsolateEntryOverride = null;
    });

    test('create works before loadModel but modelPointer throws', () async {
      final modelServer = await ModelServer.spawn();
      final brains = CowBrains<String>(
        libraryPath: '/tmp/libllama.so',
        modelServer: modelServer,
      );
      // Can create brain before loading model.
      final brain = brains.create('a');
      expect(brain, isNotNull);
      // But modelPointer throws for unloaded path.
      expect(() => brains.modelPointer('/tmp/model.gguf'), throwsStateError);
      await brains.dispose();
    });

    test('modelPointer throws for unloaded model', () async {
      final modelServer = await ModelServer.spawn();
      final brains = CowBrains<String>(
        libraryPath: '/tmp/libllama.so',
        modelServer: modelServer,
      );
      expect(() => brains.modelPointer('/tmp/model.gguf'), throwsStateError);
      await brains.dispose();
    });

    test('creates, reuses, removes, and disposes brains', () async {
      final modelServer = await ModelServer.spawn();
      final brains = CowBrains<String>(
        libraryPath: '/tmp/libllama.so',
        modelServer: modelServer,
      );

      // Load model first.
      const modelPath = '/tmp/model.gguf';
      final model = await brains.loadModel(modelPath: modelPath);
      expect(model.modelPointer, isPositive);
      expect(model.modelPath, modelPath);
      expect(brains.modelPointer(modelPath), model.modelPointer);

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
        modelHandle: model.modelPointer,
        options: _runtimeOptions(),
        profile: ModelProfileId.qwen3,
        tools: const <ToolDefinition>[],
        settings: _settings(),
        enableReasoning: true,
      );
      await brainB.init(
        modelHandle: model.modelPointer,
        options: _runtimeOptions(),
        profile: ModelProfileId.qwen3,
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

LlamaCppRuntimeOptions _runtimeOptions() {
  return const LlamaCppRuntimeOptions(
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
