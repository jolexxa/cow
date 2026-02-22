import 'dart:isolate';

import 'package:cow_brain/src/isolate/brain_harness.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

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
        final userMessage = request.runTurn!.userMessage;
        if (userMessage.content == 'error') {
          sendPort.send(const AgentError(error: 'boom').toJson());
          return;
        }
        const turnId = 'turn-1';
        sendPort.send(const AgentStepStarted(turnId: turnId, step: 1).toJson());
        sendPort.send(
          const AgentTextDelta(turnId: turnId, step: 1, text: 'hi').toJson(),
        );
        sendPort.send(
          const AgentTurnFinished(
            turnId: turnId,
            step: 1,
            finishReason: FinishReason.stop,
          ).toJson(),
        );
      case BrainRequestType.cancel:
        final turnId = request.cancel!.turnId;
        sendPort.send(
          AgentTurnFinished(
            turnId: turnId,
            step: 1,
            finishReason: FinishReason.cancelled,
          ).toJson(),
        );
      case BrainRequestType.toolResult:
      case BrainRequestType.reset:
      case BrainRequestType.dispose:
        return;
    }
  });
}

void _exitingBrainIsolate(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is! Map) return;
    final request = BrainRequest.fromJson(Map<String, Object?>.from(message));
    if (request.type == BrainRequestType.init) {
      sendPort.send(const AgentReady().toJson());
      // Exit the isolate immediately after init.
      receivePort.close();
      Isolate.exit();
    }
  });
}

void _erroringBrainIsolate(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is! Map) return;
    final request = BrainRequest.fromJson(Map<String, Object?>.from(message));
    if (request.type == BrainRequestType.init) {
      sendPort.send(const AgentReady().toJson());
      // Throw to trigger the error port.
      throw StateError('isolate crash');
    }
  });
}

void _slowBrainIsolate(SendPort sendPort) {
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
          const AgentStepStarted(turnId: 'turn-1', step: 1).toJson(),
        );
      case BrainRequestType.cancel:
      case BrainRequestType.toolResult:
      case BrainRequestType.reset:
      case BrainRequestType.dispose:
        return;
    }
  });
}

void main() {
  group('BrainHarness', () {
    test('init waits for ready event', () async {
      final harness = BrainHarness(entrypoint: _fakeBrainIsolate);
      expect(harness.events, isA<Stream<AgentEvent>>());
      await harness.init(
        modelHandle: 1,
        options: _runtimeOptions(),
        profile: ModelProfileId.qwen3,
        tools: const <ToolDefinition>[],
        settings: _settings(),
        enableReasoning: true,
      );
      await harness.dispose();
    });

    test('runTurn streams events and completes on turn_finished', () async {
      final harness = BrainHarness(entrypoint: _fakeBrainIsolate);
      await harness.init(
        modelHandle: 1,
        options: _runtimeOptions(),
        profile: ModelProfileId.qwen3,
        tools: const <ToolDefinition>[],
        settings: _settings(),
        enableReasoning: true,
      );

      final events = await harness
          .runTurn(
            userMessage: const Message(role: Role.user, content: 'hello'),
            settings: _settings(),
            enableReasoning: true,
          )
          .toList();

      expect(events.map((e) => e.runtimeType), [
        AgentStepStarted,
        AgentTextDelta,
        AgentTurnFinished,
      ]);

      await harness.dispose();
    });

    test('runTurn terminates on error without turn id', () async {
      final harness = BrainHarness(entrypoint: _fakeBrainIsolate);
      await harness.init(
        modelHandle: 1,
        options: _runtimeOptions(),
        profile: ModelProfileId.qwen3,
        tools: const <ToolDefinition>[],
        settings: _settings(),
        enableReasoning: true,
      );

      final events = await harness
          .runTurn(
            userMessage: const Message(role: Role.user, content: 'error'),
            settings: _settings(),
            enableReasoning: true,
          )
          .toList();

      expect(events, hasLength(1));
      expect(events.single, isA<AgentError>());

      await harness.dispose();
    });

    test('runTurn requires init', () {
      final harness = BrainHarness(entrypoint: _fakeBrainIsolate);
      expect(
        () => harness.runTurn(
          userMessage: const Message(role: Role.user, content: 'hello'),
          settings: _settings(),
          enableReasoning: true,
        ),
        throwsStateError,
      );
    });

    test('reset/cancel/toolResult require init', () {
      final harness = BrainHarness(entrypoint: _fakeBrainIsolate);
      expect(harness.reset, throwsStateError);
      expect(() => harness.cancel('turn-1'), throwsStateError);
      expect(
        () => harness.sendToolResult(
          turnId: 'turn-1',
          toolResult: const ToolResult(
            toolCallId: 'call-1',
            name: 'search',
            content: 'ok',
          ),
        ),
        throwsStateError,
      );
    });

    test('runTurn refuses when a turn is active', () async {
      final harness = BrainHarness(entrypoint: _slowBrainIsolate);
      await harness.init(
        modelHandle: 1,
        options: _runtimeOptions(),
        profile: ModelProfileId.qwen3,
        tools: const <ToolDefinition>[],
        settings: _settings(),
        enableReasoning: true,
      );

      harness.runTurn(
        userMessage: const Message(role: Role.user, content: 'hello'),
        settings: _settings(),
        enableReasoning: true,
      );

      expect(
        () => harness.runTurn(
          userMessage: const Message(role: Role.user, content: 'again'),
          settings: _settings(),
          enableReasoning: true,
        ),
        throwsStateError,
      );

      await harness.dispose();
    });

    test('dispose is idempotent', () async {
      final harness = BrainHarness(entrypoint: _fakeBrainIsolate);
      await harness.init(
        modelHandle: 1,
        options: _runtimeOptions(),
        profile: ModelProfileId.qwen3,
        tools: const <ToolDefinition>[],
        settings: _settings(),
        enableReasoning: true,
      );
      await harness.dispose();
      await harness.dispose();
    });

    test('operations after dispose throw', () async {
      final harness = BrainHarness(entrypoint: _fakeBrainIsolate);
      await harness.init(
        modelHandle: 1,
        options: _runtimeOptions(),
        profile: ModelProfileId.qwen3,
        tools: const <ToolDefinition>[],
        settings: _settings(),
        enableReasoning: true,
      );
      await harness.dispose();
      expect(
        () => harness.runTurn(
          userMessage: const Message(role: Role.user, content: 'hello'),
          settings: _settings(),
          enableReasoning: true,
        ),
        throwsStateError,
      );
    });

    test('emits error when isolate exits unexpectedly', () async {
      final harness = BrainHarness(entrypoint: _exitingBrainIsolate);
      await harness.init(
        modelHandle: 1,
        options: _runtimeOptions(),
        profile: ModelProfileId.qwen3,
        tools: const <ToolDefinition>[],
        settings: _settings(),
        enableReasoning: true,
      );

      // The isolate exits immediately after init — should trigger the exit
      // port listener and emit an error on the events stream.
      await expectLater(
        harness.events,
        emitsError(isA<StateError>()),
      );

      await harness.dispose();
    });

    test('emits error when isolate throws', () async {
      final harness = BrainHarness(entrypoint: _erroringBrainIsolate);
      await harness.init(
        modelHandle: 1,
        options: _runtimeOptions(),
        profile: ModelProfileId.qwen3,
        tools: const <ToolDefinition>[],
        settings: _settings(),
        enableReasoning: true,
      );

      await expectLater(
        harness.events,
        emitsError(isA<StateError>()),
      );

      await harness.dispose();
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
