import 'dart:async';
import 'dart:isolate';

import 'package:cow_brain/src/isolate/brain_harness.dart';
import 'package:cow_brain/src/isolate/brain_harness_logic.dart';
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
      case BrainRequestType.createSequence:
      case BrainRequestType.destroySequence:
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

void _failingInitBrainIsolate(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is! Map) return;
    final request = BrainRequest.fromJson(Map<String, Object?>.from(message));
    if (request.type == BrainRequestType.init) {
      sendPort.send(const AgentError(error: 'init exploded').toJson());
    }
  });
}

void _silentBrainIsolate(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  // Never responds to any requests — triggers timeout.
  receivePort.listen((_) {});
}

void _exitOnInitIsolate(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is! Map) return;
    final request = BrainRequest.fromJson(Map<String, Object?>.from(message));
    if (request.type == BrainRequestType.init) {
      // Exit without sending ready — triggers exit port before ready completes.
      receivePort.close();
      Isolate.exit();
    }
  });
}

/// Sends a telemetry event before the ready event during init.
void _chattyInitIsolate(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is! Map) return;
    final request = BrainRequest.fromJson(Map<String, Object?>.from(message));
    if (request.type == BrainRequestType.init) {
      // Emit a non-ready, non-error event before ready.
      sendPort
        ..send(
          const AgentTelemetryUpdate(
            turnId: 'pre-init',
            step: 0,
            promptTokens: 0,
            budgetTokens: 0,
            remainingTokens: 0,
            contextSize: 0,
            maxOutputTokens: 0,
            safetyMarginTokens: 0,
          ).toJson(),
        )
        ..send(const AgentReady().toJson());
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
      case BrainRequestType.createSequence:
      case BrainRequestType.destroySequence:
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
        systemPrompt: 'You are a test assistant.',
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
        systemPrompt: 'You are a test assistant.',
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
        systemPrompt: 'You are a test assistant.',
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
      expect(() => harness.cancel(turnId: 'turn-1'), throwsStateError);
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

    test('createSequence/destroySequence require init', () {
      final harness = BrainHarness(entrypoint: _fakeBrainIsolate);
      expect(
        () => harness.createSequence(sequenceId: 1),
        throwsStateError,
      );
      expect(
        () => harness.destroySequence(1),
        throwsStateError,
      );
    });

    test('createSequence/destroySequence after dispose throw', () async {
      final harness = BrainHarness(entrypoint: _fakeBrainIsolate);
      await harness.init(
        modelHandle: 1,
        options: _runtimeOptions(),
        profile: ModelProfileId.qwen3,
        tools: const <ToolDefinition>[],
        settings: _settings(),
        enableReasoning: true,
        systemPrompt: 'You are a test assistant.',
      );
      await harness.dispose();
      expect(
        () => harness.createSequence(sequenceId: 1),
        throwsStateError,
      );
      expect(
        () => harness.destroySequence(1),
        throwsStateError,
      );
    });

    test('createSequence and destroySequence send messages', () async {
      final harness = BrainHarness(entrypoint: _fakeBrainIsolate);
      await harness.init(
        modelHandle: 1,
        options: _runtimeOptions(),
        profile: ModelProfileId.qwen3,
        tools: const <ToolDefinition>[],
        settings: _settings(),
        enableReasoning: true,
        systemPrompt: 'You are a test assistant.',
      );

      // These just send messages — no response expected from the fake isolate.
      harness
        ..createSequence(sequenceId: 1, forkFrom: 0)
        ..destroySequence(1);

      await harness.dispose();
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
        systemPrompt: 'You are a test assistant.',
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
        systemPrompt: 'You are a test assistant.',
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
        systemPrompt: 'You are a test assistant.',
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

    test('init propagates error when isolate reports failure', () async {
      final harness = BrainHarness(entrypoint: _failingInitBrainIsolate);
      await expectLater(
        harness.init(
          modelHandle: 1,
          options: _runtimeOptions(),
          profile: ModelProfileId.qwen3,
          tools: const <ToolDefinition>[],
          settings: _settings(),
          enableReasoning: true,
          systemPrompt: 'You are a test assistant.',
        ),
        throwsA(isA<StateError>()),
      );
      await harness.dispose();
    });

    test('init times out when isolate never responds', () async {
      final harness = BrainHarness(
        entrypoint: _silentBrainIsolate,
        initTimeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        harness.init(
          modelHandle: 1,
          options: _runtimeOptions(),
          profile: ModelProfileId.qwen3,
          tools: const <ToolDefinition>[],
          settings: _settings(),
          enableReasoning: true,
          systemPrompt: 'You are a test assistant.',
        ),
        throwsA(isA<TimeoutException>()),
      );
      await harness.dispose();
    });

    test('init propagates error when isolate exits before ready', () async {
      final harness = BrainHarness(entrypoint: _exitOnInitIsolate);
      await expectLater(
        harness.init(
          modelHandle: 1,
          options: _runtimeOptions(),
          profile: ModelProfileId.qwen3,
          tools: const <ToolDefinition>[],
          settings: _settings(),
          enableReasoning: true,
          systemPrompt: 'You are a test assistant.',
        ),
        throwsA(isA<StateError>()),
      );
      await harness.dispose();
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
        systemPrompt: 'You are a test assistant.',
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
        systemPrompt: 'You are a test assistant.',
      );

      await expectLater(
        harness.events,
        emitsError(isA<StateError>()),
      );

      await harness.dispose();
    });

    test('forwards non-ready events during init to events stream', () async {
      final harness = BrainHarness(entrypoint: _chattyInitIsolate);

      // Listen for events before init so we don't miss the telemetry event.
      final eventsFuture = harness.events
          .where((e) => e.type == AgentEventType.telemetryUpdate)
          .first;

      await harness.init(
        modelHandle: 1,
        options: _runtimeOptions(),
        profile: ModelProfileId.qwen3,
        tools: const <ToolDefinition>[],
        settings: _settings(),
        enableReasoning: true,
        systemPrompt: 'You are a test assistant.',
      );

      final telemetryEvent = await eventsFuture;
      expect(telemetryEvent, isA<AgentTelemetryUpdate>());

      await harness.dispose();
    });

    test('re-init from ready state re-initializes', () async {
      final harness = BrainHarness(entrypoint: _fakeBrainIsolate);
      await harness.init(
        modelHandle: 1,
        options: _runtimeOptions(),
        profile: ModelProfileId.qwen3,
        tools: const <ToolDefinition>[],
        settings: _settings(),
        enableReasoning: true,
        systemPrompt: 'You are a test assistant.',
      );

      // Re-init with different params — should succeed.
      await harness.init(
        modelHandle: 2,
        options: _runtimeOptions(),
        profile: ModelProfileId.qwen3,
        tools: const <ToolDefinition>[],
        settings: _settings(),
        enableReasoning: false,
        systemPrompt: 'You are a test assistant.',
      );

      // Should still work after re-init.
      final events = await harness
          .runTurn(
            userMessage: const Message(role: Role.user, content: 'hello'),
            settings: _settings(),
            enableReasoning: true,
          )
          .toList();
      expect(events, isNotEmpty);

      await harness.dispose();
    });
  });

  group('BrainHarnessLogic state handlers', () {
    tearDown(() {
      // Reset the shim after each test.
      spawnIsolate = defaultSpawnIsolate;
    });

    test('StartingState stores isolate on HarnessIsolateSpawned', () {
      final state = StartingState();
      final ctx = state.createFakeContext();
      final data = BrainHarnessData(entrypoint: _fakeBrainIsolate);
      ctx.set(data);

      final isolate = Isolate.current;
      state.handleInput(HarnessIsolateSpawned(isolate: isolate));

      expect(data.isolate, same(isolate));

      // Clean up ports created by BrainHarnessData.
      data.receivePort.close();
      data.exitPort.close();
      data.errorPort.close();
    });

    test('spawn failure delivers HarnessIsolateDied input', () async {
      // Override the shim so Isolate.spawn "fails".
      spawnIsolate = (_, _, {onExit, onError}) async {
        throw Exception('spawn failed');
      };

      final state = NotStartedState();
      final ctx = state.createFakeContext();
      final data = BrainHarnessData(entrypoint: _fakeBrainIsolate);
      ctx.set(data);

      state.handleInput(
        HarnessInit(
          request: BrainRequest(
            type: BrainRequestType.init,
            init: InitRequest(
              modelHandle: 1,
              options: _runtimeOptions(),
              profile: ModelProfileId.qwen3,
              tools: const <ToolDefinition>[],
              settings: _settings(),
              enableReasoning: true,
              systemPrompt: 'You are a test assistant.',
            ),
          ),
        ),
      );

      // Wait for the async spawn future to resolve its error.
      await ctx.task;

      expect(ctx.inputs, hasLength(1));
      expect(ctx.inputs.first, isA<HarnessIsolateDied>());

      // Clean up ports (no real isolate was spawned).
      data.receivePort.close();
      data.exitPort.close();
      data.errorPort.close();
    });

    test('ReadyState stores isolate on HarnessIsolateSpawned', () {
      final state = ReadyState();
      final ctx = state.createFakeContext();
      final data = BrainHarnessData(entrypoint: _fakeBrainIsolate);
      ctx.set(data);

      final isolate = Isolate.current;
      state.handleInput(HarnessIsolateSpawned(isolate: isolate));

      expect(data.isolate, same(isolate));

      // Clean up ports created by BrainHarnessData.
      data.receivePort.close();
      data.exitPort.close();
      data.errorPort.close();
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
