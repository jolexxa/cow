import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:cow_brain/src/adapters/mlx/mlx.dart';
import 'package:cow_brain/src/agent/agent.dart';
import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/core/core.dart';
import 'package:cow_brain/src/isolate/brain_isolate.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/tools/tools.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_mlx_bindings.dart';

const _defaultSettings = AgentSettings(
  safetyMarginTokens: 64,
  maxSteps: 8,
);

const _runtimeOptions = LlamaCppRuntimeOptions(
  modelPath: '/tmp/model.gguf',
  libraryPath: '/tmp/libllama.so',
  contextOptions: LlamaContextOptions(
    contextSize: 2048,
    nBatch: 64,
    nThreads: 8,
    nThreadsBatch: 8,
  ),
);

final class _FakeRuntime implements BrainRuntime {
  int resetCalls = 0;
  int disposeCalls = 0;

  @override
  void reset() {
    resetCalls += 1;
  }

  @override
  void dispose() {
    disposeCalls += 1;
  }
}

final class _FakeAgentRunner implements AgentRunner {
  _FakeAgentRunner({
    required this.contextSize,
    required this.maxOutputTokens,
  });

  final StreamController<AgentEvent> controller =
      StreamController<AgentEvent>();

  @override
  final int contextSize;

  @override
  final int maxOutputTokens;

  @override
  Stream<AgentEvent> runTurn(
    Conversation convo, {
    ToolExecutor? toolExecutor,
    bool Function()? shouldCancel,
    int maxSteps = 8,
    bool enableReasoning = true,
  }) => controller.stream;
}

final class _ToolAgentRunner implements AgentRunner {
  _ToolAgentRunner({
    required this.contextSize,
    required this.maxOutputTokens,
  });

  final StreamController<AgentEvent> controller =
      StreamController<AgentEvent>();
  final Completer<void> _toolCallStarted = Completer<void>();
  ToolExecutor? _toolExecutor;

  @override
  final int contextSize;

  @override
  final int maxOutputTokens;

  @override
  Stream<AgentEvent> runTurn(
    Conversation convo, {
    ToolExecutor? toolExecutor,
    bool Function()? shouldCancel,
    int maxSteps = 8,
    bool enableReasoning = true,
  }) {
    _toolExecutor = toolExecutor;
    unawaited(_runToolCall());
    return controller.stream;
  }

  Future<void> get onToolCallStarted => _toolCallStarted.future;

  Future<void> _runToolCall() async {
    try {
      if (!_toolCallStarted.isCompleted) {
        _toolCallStarted.complete();
      }
      final executor = _toolExecutor!;
      final results = await executor(const [
        ToolCall(
          id: 'tool-1',
          name: 'search',
          arguments: {'q': 'hi'},
        ),
      ]);
      controller
        ..add(
          AgentToolResult(
            turnId: 'turn-1',
            step: 1,
            result: results.first,
          ),
        )
        ..add(
          const AgentTurnFinished(
            turnId: 'turn-1',
            step: 1,
            finishReason: FinishReason.stop,
          ),
        );
    } finally {
      await controller.close();
    }
  }
}

final class _FakeLlmAdapter implements LlmAdapter {
  @override
  Stream<ModelOutput> next({
    required List<Message> messages,
    required List<ToolDefinition> tools,
    required bool systemApplied,
    required bool enableReasoning,
    required LlmConfig config,
  }) {
    return const Stream<ModelOutput>.empty();
  }
}

final class _FakeContextManager implements ContextManager {
  @override
  ContextSlice prepare({
    required List<Message> messages,
    required List<ToolDefinition> tools,
    required int contextSize,
    required int maxOutputTokens,
    required bool systemApplied,
    ContextSlice? previousSlice,
  }) {
    return ContextSlice(
      messages: messages,
      estimatedPromptTokens: messages.length,
      droppedMessageCount: 0,
      contextSize: contextSize,
      maxOutputTokens: maxOutputTokens,
      safetyMarginTokens: 0,
      budgetTokens: contextSize - maxOutputTokens,
      remainingTokens: contextSize - maxOutputTokens - messages.length,
      reusePrefixMessageCount: 0,
      requiresReset: false,
    );
  }
}

final class _MockLlamaClient extends Mock implements LlamaClientApi {}

final class _MockBindings extends Mock implements LlamaBindings {}

final class _FakeMlxClient implements MlxClientApi {
  @override
  MlxHandles loadModel({
    required String modelPath,
    MlxModelLoadProgressCallback? onProgress,
  }) => throw UnimplementedError();

  @override
  List<int> tokenize(
    MlxHandles handles,
    String text, {
    bool addSpecial = true,
  }) => [1, 2, 3];

  @override
  int createContext(MlxHandles handles, int maxTokens) => 10;

  @override
  void resetContext(MlxHandles handles, int maxTokens) {}

  @override
  bool isEog(MlxHandles handles, int token) => false;

  @override
  void generateBegin(
    MlxHandles handles,
    List<int> tokens,
    SamplingOptions options,
  ) {}

  @override
  String? generateNext(MlxHandles handles, {int bufferSize = 256}) => null;

  @override
  void dispose(MlxHandles handles) {}
}

final class _ThrowingAgentRunner implements AgentRunner {
  _ThrowingAgentRunner({
    required this.contextSize,
    required this.maxOutputTokens,
  });

  @override
  final int contextSize;

  @override
  final int maxOutputTokens;

  @override
  Stream<AgentEvent> runTurn(
    Conversation convo, {
    ToolExecutor? toolExecutor,
    bool Function()? shouldCancel,
    int maxSteps = 8,
    bool enableReasoning = true,
  }) {
    return Stream<AgentEvent>.error(StateError('boom'));
  }
}

final class _CancelAwareAgentRunner implements AgentRunner {
  _CancelAwareAgentRunner({
    required this.contextSize,
    required this.maxOutputTokens,
  });

  final StreamController<AgentEvent> controller =
      StreamController<AgentEvent>();
  ToolExecutor? _toolExecutor;

  @override
  final int contextSize;

  @override
  final int maxOutputTokens;

  @override
  Stream<AgentEvent> runTurn(
    Conversation convo, {
    ToolExecutor? toolExecutor,
    bool Function()? shouldCancel,
    int maxSteps = 8,
    bool enableReasoning = true,
  }) {
    _toolExecutor = toolExecutor;
    unawaited(_runToolCall());
    return controller.stream;
  }

  Future<void> _runToolCall() async {
    try {
      final executor = _toolExecutor!;
      await executor(const [
        ToolCall(
          id: 'tool-1',
          name: 'search',
          arguments: {'q': 'hi'},
        ),
      ]);
      controller.add(
        const AgentTurnFinished(
          turnId: 'turn-1',
          step: 1,
          finishReason: FinishReason.stop,
        ),
      );
    } on Object catch (error) {
      controller.add(AgentError(error: error.toString()));
    } finally {
      await controller.close();
    }
  }
}

AgentBundle _bundleWith(
  AgentRunner agent, {
  required Conversation conversation,
  required ToolRegistry tools,
  BrainRuntime? runtime,
}) {
  return (
    agent: agent,
    conversation: conversation,
    llm: _FakeLlmAdapter(),
    tools: tools,
    context: _FakeContextManager(),
    runtime: runtime ?? _FakeRuntime(),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const LlamaModelOptions());
    registerFallbackValue(Pointer<llama_model>.fromAddress(0));
    registerFallbackValue(Pointer<llama_context>.fromAddress(0));
    registerFallbackValue(
      LlamaHandles(
        bindings: _MockBindings(),
        model: Pointer.fromAddress(0),
        context: Pointer.fromAddress(0),
        vocab: Pointer.fromAddress(0),
      ),
    );
    registerFallbackValue(
      const LlamaContextOptions(
        contextSize: 1,
        nBatch: 1,
        nThreads: 1,
        nThreadsBatch: 1,
      ),
    );
  });

  group('_BrainIsolate', () {
    test('ignores non-map messages', () {
      final receivePort = ReceivePort();

      BrainIsolateTestHarness(
        receivePort.sendPort,
        bundleFactory: _fakeBundleFactory,
      ).handleMessage('nope');

      receivePort.close();
    });

    test('init without payload emits an error', () async {
      final receivePort = ReceivePort();
      BrainIsolateTestHarness(
        receivePort.sendPort,
        bundleFactory: _fakeBundleFactory,
      ).handleMessage(
        const BrainRequest(type: BrainRequestType.init).toJson(),
      );

      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(await receivePort.first as Map),
      );
      expect(event, isA<AgentError>());
      expect((event as AgentError).error, contains('Init payload'));
      receivePort.close();
    });

    test('run_turn before init emits an error', () async {
      final receivePort = ReceivePort();
      BrainIsolateTestHarness(
        receivePort.sendPort,
        bundleFactory: _fakeBundleFactory,
      ).handleMessage(
        BrainRequest(
          type: BrainRequestType.runTurn,
          runTurn: _runTurnRequest(
            userMessage: const Message(role: Role.user, content: 'hi'),
          ),
        ).toJson(),
      );

      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(await receivePort.first as Map),
      );
      expect(event, isA<AgentError>());
      expect((event as AgentError).error, contains('not initialized'));
      receivePort.close();
    });

    test('init sends ready and registers tools', () async {
      final receivePort = ReceivePort();
      final iterator = StreamIterator(receivePort);
      final recorded = <ToolDefinition>[];
      late ToolRegistry capturedTools;

      BrainIsolateTestHarness(
        receivePort.sendPort,
        bundleFactory:
            ({
              required int modelPointer,
              required BackendRuntimeOptions options,
              required ModelProfileId profile,
              required ToolRegistry tools,
              required Conversation conversation,
              required int contextSize,
              required int maxOutputTokens,
              required double temperature,
              required int safetyMarginTokens,
            }) {
              recorded.addAll(tools.definitions);
              capturedTools = tools;
              return _fakeBundleFactory(
                modelPointer: modelPointer,
                options: options,
                profile: profile,
                tools: tools,
                conversation: conversation,
                contextSize: contextSize,
                maxOutputTokens: maxOutputTokens,
                temperature: temperature,
                safetyMarginTokens: safetyMarginTokens,
              );
            },
      ).handleMessage(
        BrainRequest(
          type: BrainRequestType.init,
          init: _initRequest(
            tools: const [
              ToolDefinition(
                name: 'search',
                description: 'Search',
                parameters: {'type': 'object'},
              ),
            ],
          ),
        ).toJson(),
      );

      await iterator.moveNext();
      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(iterator.current as Map),
      );
      expect(event, isA<AgentReady>());
      expect(recorded.single.name, 'search');

      final results = await capturedTools.executeAll(
        const [
          ToolCall(
            id: 'tool-1',
            name: 'search',
            arguments: {'q': 'hi'},
          ),
        ],
      );
      expect(results.single.isError, isTrue);
      await iterator.cancel();
      receivePort.close();
    });

    test('init with profile yields ready', () async {
      final receivePort = ReceivePort();
      final iterator = StreamIterator(receivePort);

      BrainIsolateTestHarness(
        receivePort.sendPort,
        bundleFactory: _fakeBundleFactory,
      ).handleMessage(
        BrainRequest(
          type: BrainRequestType.init,
          init: _initRequest(),
        ).toJson(),
      );

      await iterator.moveNext();
      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(iterator.current as Map),
      );
      expect(event, isA<AgentReady>());
      await iterator.cancel();
      receivePort.close();
    });

    test('init twice disposes previous runtime', () async {
      final receivePort = ReceivePort();
      final iterator = StreamIterator(receivePort);
      final runtime = _FakeRuntime();
      var bundleCalls = 0;
      final harness = BrainIsolateTestHarness(
        receivePort.sendPort,
        bundleFactory:
            ({
              required int modelPointer,
              required BackendRuntimeOptions options,
              required ModelProfileId profile,
              required ToolRegistry tools,
              required Conversation conversation,
              required int contextSize,
              required int maxOutputTokens,
              required double temperature,
              required int safetyMarginTokens,
            }) {
              bundleCalls += 1;
              return _bundleWith(
                _FakeAgentRunner(
                  contextSize: 128,
                  maxOutputTokens: 32,
                ),
                conversation: conversation,
                tools: tools,
                runtime: runtime,
              );
            },
      );

      final initMessage = BrainRequest(
        type: BrainRequestType.init,
        init: _initRequest(),
      );

      harness.handleMessage(initMessage.toJson());
      await iterator.moveNext();
      harness.handleMessage(initMessage.toJson());
      await iterator.moveNext();

      expect(bundleCalls, 2);
      expect(runtime.disposeCalls, 1);
      await iterator.cancel();
      receivePort.close();
    });

    test('run_turn forwards agent events', () async {
      final receivePort = ReceivePort();
      final iterator = StreamIterator(receivePort);
      final fakeAgent = _FakeAgentRunner(
        contextSize: 128,
        maxOutputTokens: 32,
      );
      final harness =
          BrainIsolateTestHarness(
            receivePort.sendPort,
            bundleFactory:
                ({
                  required int modelPointer,
                  required BackendRuntimeOptions options,
                  required ModelProfileId profile,
                  required ToolRegistry tools,
                  required Conversation conversation,
                  required int contextSize,
                  required int maxOutputTokens,
                  required double temperature,
                  required int safetyMarginTokens,
                }) {
                  return _bundleWith(
                    fakeAgent,
                    conversation: conversation,
                    tools: tools,
                  );
                },
          )..handleMessage(
            BrainRequest(
              type: BrainRequestType.init,
              init: _initRequest(),
            ).toJson(),
          );
      await iterator.moveNext();

      harness.handleMessage(
        BrainRequest(
          type: BrainRequestType.runTurn,
          runTurn: _runTurnRequest(
            userMessage: const Message(role: Role.user, content: 'hi'),
          ),
        ).toJson(),
      );

      fakeAgent.controller
        ..add(const AgentStepStarted(turnId: 'turn-1', step: 1))
        ..add(
          const AgentTurnFinished(
            turnId: 'turn-1',
            step: 1,
            finishReason: FinishReason.stop,
          ),
        );

      await fakeAgent.controller.close();

      final events = <AgentEvent>[];
      for (var i = 0; i < 2; i += 1) {
        await iterator.moveNext();
        final message = iterator.current;
        events.add(
          AgentEvent.fromJson(Map<String, Object?>.from(message as Map)),
        );
      }

      expect(events.first, isA<AgentStepStarted>());
      expect(events.last, isA<AgentTurnFinished>());
      await iterator.cancel();
      receivePort.close();
    });

    test('run_turn rejects non-user role messages', () async {
      final receivePort = ReceivePort();
      final iterator = StreamIterator(receivePort);
      final harness =
          BrainIsolateTestHarness(
            receivePort.sendPort,
            bundleFactory: _fakeBundleFactory,
          )..handleMessage(
            BrainRequest(
              type: BrainRequestType.init,
              init: _initRequest(),
            ).toJson(),
          );
      await iterator.moveNext();

      harness.handleMessage(
        BrainRequest(
          type: BrainRequestType.runTurn,
          runTurn: _runTurnRequest(
            userMessage: const Message(role: Role.assistant, content: 'nope'),
          ),
        ).toJson(),
      );

      await iterator.moveNext();
      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(iterator.current as Map),
      );
      expect(event, isA<AgentError>());
      expect((event as AgentError).error, contains('user message'));
      await iterator.cancel();
      receivePort.close();
    });

    test('init uses the default bundle factory', () async {
      final receivePort = ReceivePort();
      final iterator = StreamIterator(receivePort);
      final client = _MockLlamaClient();
      final bindings = _MockBindings();
      final handles = LlamaHandles(
        bindings: bindings,
        model: Pointer.fromAddress(1),
        context: Pointer.fromAddress(2),
        vocab: Pointer.fromAddress(3),
      );

      when(
        () => client.loadModel(
          modelPath: any(named: 'modelPath'),
          modelOptions: any(named: 'modelOptions'),
        ),
      ).thenReturn(handles);
      when(
        () => client.createContext(any(), any()),
      ).thenReturn(Pointer.fromAddress(2));
      when(() => client.dispose(handles)).thenReturn(null);
      when(
        () => bindings.llama_model_get_vocab(any()),
      ).thenReturn(Pointer.fromAddress(3));
      when(() => bindings.llama_free(any())).thenReturn(null);

      final previousClientOverride = brainRuntimeClientOverride;
      final previousBindingsOverride = brainRuntimeBindingsOverride;
      brainRuntimeClientOverride = client;
      brainRuntimeBindingsOverride = bindings;
      addTearDown(() {
        brainRuntimeClientOverride = previousClientOverride;
        brainRuntimeBindingsOverride = previousBindingsOverride;
      });

      final harness = BrainIsolateTestHarness(receivePort.sendPort)
        ..handleMessage(
          BrainRequest(
            type: BrainRequestType.init,
            init: _initRequest(),
          ).toJson(),
        );

      await iterator.moveNext();
      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(iterator.current as Map),
      );
      expect(event, isA<AgentReady>());

      harness.handleMessage(
        const BrainRequest(type: BrainRequestType.dispose).toJson(),
      );

      await iterator.cancel();
      receivePort.close();
    });

    test('creates MlxRuntime for MlxRuntimeOptions', () async {
      final receivePort = ReceivePort();
      final iterator = StreamIterator(receivePort);
      final mlxBindings = FakeMlxBindings(
        modelFromIdResult: 5,
      );
      final mlxClient = _FakeMlxClient();

      final previousClientOverride = brainMlxRuntimeClientOverride;
      final previousBindingsOverride = brainMlxRuntimeBindingsOverride;
      brainMlxRuntimeClientOverride = mlxClient;
      brainMlxRuntimeBindingsOverride = mlxBindings;
      addTearDown(() {
        brainMlxRuntimeClientOverride = previousClientOverride;
        brainMlxRuntimeBindingsOverride = previousBindingsOverride;
      });

      const mlxOptions = MlxRuntimeOptions(
        modelPath: '/tmp/model.mlx',
        libraryPath: '/tmp/libmlx.dylib',
        contextSize: 2048,
      );

      final harness = BrainIsolateTestHarness(receivePort.sendPort)
        ..handleMessage(
          const BrainRequest(
            type: BrainRequestType.init,
            init: InitRequest(
              modelHandle: 5,
              options: mlxOptions,
              profile: ModelProfileId.qwen3,
              tools: [],
              settings: _defaultSettings,
              enableReasoning: true,
            ),
          ).toJson(),
        );

      await iterator.moveNext();
      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(iterator.current as Map),
      );
      expect(event, isA<AgentReady>());

      harness.handleMessage(
        const BrainRequest(type: BrainRequestType.dispose).toJson(),
      );

      await iterator.cancel();
      receivePort.close();
    });

    test('run_turn without payload emits error', () async {
      final receivePort = ReceivePort();

      BrainIsolateTestHarness(
        receivePort.sendPort,
        bundleFactory: _fakeBundleFactory,
      ).handleMessage(
        const BrainRequest(type: BrainRequestType.runTurn).toJson(),
      );

      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(await receivePort.first as Map),
      );
      expect(event, isA<AgentError>());
      expect((event as AgentError).error, contains('RunTurn payload'));
      receivePort.close();
    });

    test('run_turn error from agent is forwarded', () async {
      final receivePort = ReceivePort();
      final iterator = StreamIterator(receivePort);
      final harness =
          BrainIsolateTestHarness(
            receivePort.sendPort,
            bundleFactory:
                ({
                  required int modelPointer,
                  required BackendRuntimeOptions options,
                  required ModelProfileId profile,
                  required ToolRegistry tools,
                  required Conversation conversation,
                  required int contextSize,
                  required int maxOutputTokens,
                  required double temperature,
                  required int safetyMarginTokens,
                }) {
                  return _bundleWith(
                    _ThrowingAgentRunner(
                      contextSize: contextSize,
                      maxOutputTokens: maxOutputTokens,
                    ),
                    conversation: conversation,
                    tools: tools,
                  );
                },
          )..handleMessage(
            BrainRequest(
              type: BrainRequestType.init,
              init: _initRequest(),
            ).toJson(),
          );
      await iterator.moveNext();

      harness.handleMessage(
        BrainRequest(
          type: BrainRequestType.runTurn,
          runTurn: _runTurnRequest(
            userMessage: const Message(role: Role.user, content: 'hi'),
          ),
        ).toJson(),
      );

      await iterator.moveNext();
      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(iterator.current as Map),
      );
      expect(event, isA<AgentError>());
      await iterator.cancel();
      receivePort.close();
    });

    test('cancel while tool call pending cancels execution', () async {
      final receivePort = ReceivePort();
      final iterator = StreamIterator(receivePort);
      final harness =
          BrainIsolateTestHarness(
            receivePort.sendPort,
            bundleFactory:
                ({
                  required int modelPointer,
                  required BackendRuntimeOptions options,
                  required ModelProfileId profile,
                  required ToolRegistry tools,
                  required Conversation conversation,
                  required int contextSize,
                  required int maxOutputTokens,
                  required double temperature,
                  required int safetyMarginTokens,
                }) {
                  return _bundleWith(
                    _CancelAwareAgentRunner(
                      contextSize: contextSize,
                      maxOutputTokens: maxOutputTokens,
                    ),
                    conversation: conversation,
                    tools: tools,
                  );
                },
          )..handleMessage(
            BrainRequest(
              type: BrainRequestType.init,
              init: _initRequest(),
            ).toJson(),
          );
      await iterator.moveNext();

      harness
        ..handleMessage(
          BrainRequest(
            type: BrainRequestType.runTurn,
            runTurn: _runTurnRequest(
              userMessage: const Message(role: Role.user, content: 'hi'),
            ),
          ).toJson(),
        )
        ..handleMessage(
          const BrainRequest(
            type: BrainRequestType.cancel,
            cancel: CancelRequest(turnId: 'turn-1'),
          ).toJson(),
        );

      await iterator.moveNext();
      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(iterator.current as Map),
      );
      expect(event, isA<AgentError>());
      await iterator.cancel();
      receivePort.close();
    });

    test('init refuses when another turn is active', () async {
      final receivePort = ReceivePort();
      final iterator = StreamIterator(receivePort);
      final fakeAgent = _FakeAgentRunner(
        contextSize: 128,
        maxOutputTokens: 32,
      );
      final harness =
          BrainIsolateTestHarness(
            receivePort.sendPort,
            bundleFactory:
                ({
                  required int modelPointer,
                  required BackendRuntimeOptions options,
                  required ModelProfileId profile,
                  required ToolRegistry tools,
                  required Conversation conversation,
                  required int contextSize,
                  required int maxOutputTokens,
                  required double temperature,
                  required int safetyMarginTokens,
                }) {
                  return _bundleWith(
                    fakeAgent,
                    conversation: conversation,
                    tools: tools,
                  );
                },
          )..handleMessage(
            BrainRequest(
              type: BrainRequestType.init,
              init: _initRequest(),
            ).toJson(),
          );
      await iterator.moveNext();

      harness
        ..handleMessage(
          BrainRequest(
            type: BrainRequestType.runTurn,
            runTurn: _runTurnRequest(
              userMessage: const Message(role: Role.user, content: 'hi'),
            ),
          ).toJson(),
        )
        ..handleMessage(
          BrainRequest(
            type: BrainRequestType.init,
            init: _initRequest(),
          ).toJson(),
        );

      await iterator.moveNext();
      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(iterator.current as Map),
      );
      expect(event, isA<AgentError>());
      expect((event as AgentError).error, contains('Turn already running'));
      await iterator.cancel();
      receivePort.close();
    });

    test('run_turn refuses when another turn is active', () async {
      final receivePort = ReceivePort();
      final iterator = StreamIterator(receivePort);
      final fakeAgent = _FakeAgentRunner(
        contextSize: 128,
        maxOutputTokens: 32,
      );
      final harness =
          BrainIsolateTestHarness(
            receivePort.sendPort,
            bundleFactory:
                ({
                  required int modelPointer,
                  required BackendRuntimeOptions options,
                  required ModelProfileId profile,
                  required ToolRegistry tools,
                  required Conversation conversation,
                  required int contextSize,
                  required int maxOutputTokens,
                  required double temperature,
                  required int safetyMarginTokens,
                }) {
                  return _bundleWith(
                    fakeAgent,
                    conversation: conversation,
                    tools: tools,
                  );
                },
          )..handleMessage(
            BrainRequest(
              type: BrainRequestType.init,
              init: _initRequest(),
            ).toJson(),
          );
      await iterator.moveNext();

      harness
        ..handleMessage(
          BrainRequest(
            type: BrainRequestType.runTurn,
            runTurn: _runTurnRequest(
              userMessage: const Message(role: Role.user, content: 'hi'),
            ),
          ).toJson(),
        )
        ..handleMessage(
          BrainRequest(
            type: BrainRequestType.runTurn,
            runTurn: _runTurnRequest(
              userMessage: const Message(role: Role.user, content: 'again'),
            ),
          ).toJson(),
        );

      await iterator.moveNext();
      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(iterator.current as Map),
      );
      expect(event, isA<AgentError>());
      expect((event as AgentError).error, contains('Turn already running'));
      await iterator.cancel();
      receivePort.close();
    });

    test('reset before init emits error', () async {
      final receivePort = ReceivePort();

      BrainIsolateTestHarness(
        receivePort.sendPort,
        bundleFactory: _fakeBundleFactory,
      ).handleMessage(
        const BrainRequest(type: BrainRequestType.reset).toJson(),
      );

      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(await receivePort.first as Map),
      );
      expect(event, isA<AgentError>());
      expect((event as AgentError).error, contains('not initialized'));
      receivePort.close();
    });

    test('reset clears state and resets runtime', () async {
      final receivePort = ReceivePort();
      final runtime = _FakeRuntime();
      final harness =
          BrainIsolateTestHarness(
            receivePort.sendPort,
            bundleFactory:
                ({
                  required int modelPointer,
                  required BackendRuntimeOptions options,
                  required ModelProfileId profile,
                  required ToolRegistry tools,
                  required Conversation conversation,
                  required int contextSize,
                  required int maxOutputTokens,
                  required double temperature,
                  required int safetyMarginTokens,
                }) {
                  return _bundleWith(
                    _FakeAgentRunner(
                      contextSize: 128,
                      maxOutputTokens: 32,
                    ),
                    conversation: conversation,
                    tools: tools,
                    runtime: runtime,
                  );
                },
          )..handleMessage(
            BrainRequest(
              type: BrainRequestType.init,
              init: _initRequest(),
            ).toJson(),
          );
      await receivePort.first;

      harness.handleMessage(
        const BrainRequest(type: BrainRequestType.reset).toJson(),
      );

      expect(runtime.resetCalls, 1);
      receivePort.close();
    });

    test('reset clears pending state', () async {
      final receivePort = ReceivePort();
      final runtime = _FakeRuntime();
      final fakeAgent = _FakeAgentRunner(
        contextSize: 128,
        maxOutputTokens: 32,
      );
      final harness =
          BrainIsolateTestHarness(
            receivePort.sendPort,
            bundleFactory:
                ({
                  required int modelPointer,
                  required BackendRuntimeOptions options,
                  required ModelProfileId profile,
                  required ToolRegistry tools,
                  required Conversation conversation,
                  required int contextSize,
                  required int maxOutputTokens,
                  required double temperature,
                  required int safetyMarginTokens,
                }) {
                  return _bundleWith(
                    fakeAgent,
                    conversation: conversation,
                    tools: tools,
                    runtime: runtime,
                  );
                },
          )..handleMessage(
            BrainRequest(
              type: BrainRequestType.init,
              init: _initRequest(),
            ).toJson(),
          );
      await receivePort.first;

      harness.handleMessage(
        const BrainRequest(type: BrainRequestType.reset).toJson(),
      );

      // Reset clears runtime state.
      expect(runtime.resetCalls, 1);
      receivePort.close();
    });

    test('cancel request without payload emits error', () async {
      final receivePort = ReceivePort();

      BrainIsolateTestHarness(
        receivePort.sendPort,
        bundleFactory: _fakeBundleFactory,
      ).handleMessage(
        const BrainRequest(type: BrainRequestType.cancel).toJson(),
      );

      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(await receivePort.first as Map),
      );
      expect(event, isA<AgentError>());
      expect((event as AgentError).error, contains('Cancel payload'));
      receivePort.close();
    });

    test('tool_result without payload emits error', () async {
      final receivePort = ReceivePort();

      BrainIsolateTestHarness(
        receivePort.sendPort,
        bundleFactory: _fakeBundleFactory,
      ).handleMessage(
        const BrainRequest(type: BrainRequestType.toolResult).toJson(),
      );

      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(await receivePort.first as Map),
      );
      expect(event, isA<AgentError>());
      expect((event as AgentError).error, contains('ToolResult payload'));
      receivePort.close();
    });

    test('tool_result completes pending call', () async {
      final receivePort = ReceivePort();
      final iterator = StreamIterator(receivePort);
      late _ToolAgentRunner agentRunner;
      final harness =
          BrainIsolateTestHarness(
            receivePort.sendPort,
            bundleFactory:
                ({
                  required int modelPointer,
                  required BackendRuntimeOptions options,
                  required ModelProfileId profile,
                  required ToolRegistry tools,
                  required Conversation conversation,
                  required int contextSize,
                  required int maxOutputTokens,
                  required double temperature,
                  required int safetyMarginTokens,
                }) {
                  agentRunner = _ToolAgentRunner(
                    contextSize: contextSize,
                    maxOutputTokens: maxOutputTokens,
                  );
                  return _bundleWith(
                    agentRunner,
                    conversation: conversation,
                    tools: tools,
                  );
                },
          )..handleMessage(
            BrainRequest(
              type: BrainRequestType.init,
              init: _initRequest(
                tools: const [
                  ToolDefinition(
                    name: 'search',
                    description: 'Search',
                    parameters: {'type': 'object'},
                  ),
                ],
              ),
            ).toJson(),
          );
      await iterator.moveNext(); // ready

      harness.handleMessage(
        BrainRequest(
          type: BrainRequestType.runTurn,
          runTurn: _runTurnRequest(
            userMessage: const Message(role: Role.user, content: 'hi'),
          ),
        ).toJson(),
      );

      await agentRunner.onToolCallStarted;

      harness.handleMessage(
        const BrainRequest(
          type: BrainRequestType.toolResult,
          toolResult: ToolResultRequest(
            turnId: 'turn-1',
            toolResult: ToolResult(
              toolCallId: 'tool-1',
              name: 'search',
              content: 'ok',
            ),
          ),
        ).toJson(),
      );

      await iterator.moveNext();
      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(iterator.current as Map),
      );
      expect(event, isA<AgentToolResult>());
      await iterator.cancel();
      receivePort.close();
    });

    test('tool_result ignores unknown tool ids', () async {
      final receivePort = ReceivePort();
      final harness =
          BrainIsolateTestHarness(
            receivePort.sendPort,
            bundleFactory: _fakeBundleFactory,
          )..handleMessage(
            BrainRequest(
              type: BrainRequestType.init,
              init: _initRequest(),
            ).toJson(),
          );
      await receivePort.first;

      harness.handleMessage(
        const BrainRequest(
          type: BrainRequestType.toolResult,
          toolResult: ToolResultRequest(
            turnId: 'turn-1',
            toolResult: ToolResult(
              toolCallId: 'unknown',
              name: 'search',
              content: 'ignored',
            ),
          ),
        ).toJson(),
      );

      receivePort.close();
    });

    test('cancel completes pending turn and dispose runs', () async {
      final receivePort = ReceivePort();
      final iterator = StreamIterator(receivePort);
      final runtime = _FakeRuntime();
      final fakeAgent = _FakeAgentRunner(
        contextSize: 128,
        maxOutputTokens: 32,
      );
      final harness =
          BrainIsolateTestHarness(
            receivePort.sendPort,
            bundleFactory:
                ({
                  required int modelPointer,
                  required BackendRuntimeOptions options,
                  required ModelProfileId profile,
                  required ToolRegistry tools,
                  required Conversation conversation,
                  required int contextSize,
                  required int maxOutputTokens,
                  required double temperature,
                  required int safetyMarginTokens,
                }) {
                  return _bundleWith(
                    fakeAgent,
                    conversation: conversation,
                    tools: tools,
                    runtime: runtime,
                  );
                },
          )..handleMessage(
            BrainRequest(
              type: BrainRequestType.init,
              init: _initRequest(),
            ).toJson(),
          );
      await iterator.moveNext();

      harness
        ..handleMessage(
          BrainRequest(
            type: BrainRequestType.runTurn,
            runTurn: _runTurnRequest(
              userMessage: const Message(role: Role.user, content: 'hi'),
            ),
          ).toJson(),
        )
        ..handleMessage(
          const BrainRequest(
            type: BrainRequestType.cancel,
            cancel: CancelRequest(turnId: 'turn-1'),
          ).toJson(),
        )
        ..handleMessage(
          const BrainRequest(type: BrainRequestType.dispose).toJson(),
        );

      expect(runtime.disposeCalls, 1);
      await iterator.cancel();
      receivePort.close();
    });

    test('reset and dispose complete pending turn when active', () async {
      final receivePort = ReceivePort();
      final iterator = StreamIterator(receivePort);
      final fakeAgent = _FakeAgentRunner(
        contextSize: 128,
        maxOutputTokens: 32,
      );
      final harness =
          BrainIsolateTestHarness(
            receivePort.sendPort,
            bundleFactory:
                ({
                  required int modelPointer,
                  required BackendRuntimeOptions options,
                  required ModelProfileId profile,
                  required ToolRegistry tools,
                  required Conversation conversation,
                  required int contextSize,
                  required int maxOutputTokens,
                  required double temperature,
                  required int safetyMarginTokens,
                }) {
                  return _bundleWith(
                    fakeAgent,
                    conversation: conversation,
                    tools: tools,
                  );
                },
          )..handleMessage(
            BrainRequest(
              type: BrainRequestType.init,
              init: _initRequest(),
            ).toJson(),
          );
      await iterator.moveNext();

      harness
        ..handleMessage(
          BrainRequest(
            type: BrainRequestType.runTurn,
            runTurn: _runTurnRequest(
              userMessage: const Message(role: Role.user, content: 'hi'),
            ),
          ).toJson(),
        )
        ..handleMessage(
          const BrainRequest(type: BrainRequestType.reset).toJson(),
        )
        ..handleMessage(
          const BrainRequest(type: BrainRequestType.dispose).toJson(),
        );

      await iterator.cancel();
      receivePort.close();
    });

    test('dispose completes cancel completer when turn is active', () async {
      final receivePort = ReceivePort();
      final iterator = StreamIterator(receivePort);
      final fakeAgent = _FakeAgentRunner(
        contextSize: 128,
        maxOutputTokens: 32,
      );
      final harness =
          BrainIsolateTestHarness(
            receivePort.sendPort,
            bundleFactory:
                ({
                  required int modelPointer,
                  required BackendRuntimeOptions options,
                  required ModelProfileId profile,
                  required ToolRegistry tools,
                  required Conversation conversation,
                  required int contextSize,
                  required int maxOutputTokens,
                  required double temperature,
                  required int safetyMarginTokens,
                }) {
                  return _bundleWith(
                    fakeAgent,
                    conversation: conversation,
                    tools: tools,
                  );
                },
          )..handleMessage(
            BrainRequest(
              type: BrainRequestType.init,
              init: _initRequest(),
            ).toJson(),
          );
      await iterator.moveNext();

      harness
        ..handleMessage(
          BrainRequest(
            type: BrainRequestType.runTurn,
            runTurn: _runTurnRequest(
              userMessage: const Message(role: Role.user, content: 'hi'),
            ),
          ).toJson(),
        )
        ..handleMessage(
          const BrainRequest(type: BrainRequestType.dispose).toJson(),
        );

      await iterator.cancel();
      receivePort.close();
    });

    test('dispose before init does not throw', () async {
      final receivePort = ReceivePort();

      BrainIsolateTestHarness(
        receivePort.sendPort,
        bundleFactory: _fakeBundleFactory,
      ).handleMessage(
        const BrainRequest(type: BrainRequestType.dispose).toJson(),
      );

      receivePort.close();
    });
  });
}

AgentBundle _fakeBundleFactory({
  required int modelPointer,
  required BackendRuntimeOptions options,
  required ModelProfileId profile,
  required ToolRegistry tools,
  required Conversation conversation,
  required int contextSize,
  required int maxOutputTokens,
  required double temperature,
  required int safetyMarginTokens,
}) {
  final fakeAgent = _FakeAgentRunner(
    contextSize: contextSize,
    maxOutputTokens: maxOutputTokens,
  );
  return _bundleWith(
    fakeAgent,
    conversation: conversation,
    tools: tools,
  );
}

InitRequest _initRequest({
  List<ToolDefinition> tools = const <ToolDefinition>[],
}) {
  return InitRequest(
    modelHandle: 1,
    options: _runtimeOptions,
    profile: ModelProfileId.qwen3,
    tools: tools,
    settings: _defaultSettings,
    enableReasoning: true,
  );
}

RunTurnRequest _runTurnRequest({required Message userMessage}) {
  return RunTurnRequest(
    userMessage: userMessage,
    settings: _defaultSettings,
    enableReasoning: true,
  );
}
