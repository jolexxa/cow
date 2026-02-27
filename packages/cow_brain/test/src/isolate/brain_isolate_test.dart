import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:cow_brain/src/adapters/inference_adapter.dart';
import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:cow_brain/src/adapters/mlx/mlx.dart';
import 'package:cow_brain/src/adapters/prompt_formatter.dart';
import 'package:cow_brain/src/adapters/stream_chunk.dart';
import 'package:cow_brain/src/adapters/stream_parser.dart';
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

/// Runtime that also implements InferenceRuntime (for multi-sequence tests).
final class _FakeInferenceRuntime implements BrainRuntime, InferenceRuntime {
  int resetCalls = 0;
  int disposeCalls = 0;
  int createSequenceCalls = 0;
  int destroySequenceCalls = 0;
  int forkSequenceCalls = 0;
  int? lastCreatedSeqId;
  int? lastDestroyedSeqId;
  ({int source, int target})? lastFork;
  bool throwOnCreate = false;
  bool throwOnFork = false;
  bool throwOnDestroy = false;

  /// Completer that delays generate until completed.
  final Map<int, Completer<void>> generateGates = {};

  @override
  void reset() => resetCalls += 1;
  @override
  void dispose() => disposeCalls += 1;

  @override
  int countTokens(String prompt, {required bool addBos}) => prompt.length;

  @override
  Stream<StreamChunk> generate({
    required String prompt,
    required List<String> stopSequences,
    required bool addBos,
    required bool requiresReset,
    required int reusePrefixMessageCount,
    int sequenceId = 0,
  }) {
    final gate = generateGates[sequenceId];
    if (gate != null) {
      return _gatedStream(gate.future);
    }
    return const Stream.empty();
  }

  Stream<StreamChunk> _gatedStream(Future<void> gate) async* {
    await gate;
    // Stream completes after gate opens.
  }

  @override
  void createSequence(int sequenceId) {
    createSequenceCalls++;
    lastCreatedSeqId = sequenceId;
    if (throwOnCreate) throw StateError('create failed');
  }

  @override
  void destroySequence(int sequenceId) {
    destroySequenceCalls++;
    lastDestroyedSeqId = sequenceId;
    if (throwOnDestroy) throw StateError('destroy failed');
  }

  @override
  void forkSequence({required int source, required int target}) {
    forkSequenceCalls++;
    lastFork = (source: source, target: target);
    if (throwOnFork) throw StateError('fork failed');
  }
}

final class _FakeFormatter implements PromptFormatter {
  @override
  String format({
    required List<Message> messages,
    required List<ToolDefinition> tools,
    required bool enableReasoning,
  }) => messages.map((m) => m.content).join('\n');

  @override
  List<String> get stopSequences => [];
  @override
  bool get addBos => false;
}

final class _FakeStreamParser implements StreamParser {
  @override
  Stream<ModelOutput> parse(Stream<StreamChunk> chunks) async* {
    // Drain the input so errors propagate.
    await for (final _ in chunks) {
      // No output produced.
    }
  }
}

/// Creates a bundle with an [AgentLoop] backed by an [InferenceAdapter],
/// which is required for multi-sequence tests (_createSequence needs
/// the existing agent to be an AgentLoop with an InferenceAdapter).
AgentBundle _agentLoopBundle({
  required _FakeInferenceRuntime runtime,
  required Conversation conversation,
  required ToolRegistry tools,
  int contextSize = 2048,
  int maxOutputTokens = 512,
}) {
  final profile = ModelProfile(
    formatter: _FakeFormatter(),
    streamParser: _FakeStreamParser(),
  );
  final adapter = InferenceAdapter(runtime: runtime, profile: profile);
  final contextManager = SlidingWindowContextManager(
    counter: adapter.tokenCounter,
    safetyMarginTokens: 64,
  );
  final agent = AgentLoop(
    llm: adapter,
    tools: tools,
    context: contextManager,
    contextSize: contextSize,
    maxOutputTokens: maxOutputTokens,
    temperature: 0.7,
  );
  return (
    agent: agent,
    conversation: conversation,
    llm: adapter,
    tools: tools,
    context: contextManager,
    runtime: runtime,
  );
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
    SamplingOptions options, {
    required int contextHandle,
  }) {}

  @override
  List<int>? generateNext(
    MlxHandles handles, {
    required int contextHandle,
    int bufferSize = 256,
  }) => null;

  @override
  void dispose(MlxHandles handles) {}

  @override
  int batchCreate(MlxHandles handles, int maxTokens) => 1;
  @override
  void batchFree(MlxHandles handles, int batchHandle) {}
  @override
  void batchAddSequence(
    MlxHandles handles,
    int batchHandle,
    int seqId,
    List<int> tokens,
  ) {}
  @override
  int batchPrefill(
    MlxHandles handles,
    int batchHandle,
    SamplingOptions options,
  ) => 0;
  @override
  Map<int, List<int>?> batchStep(
    MlxHandles handles,
    int batchHandle, {
    int maxSeqs = 16,
    int bufferSize = 4096,
  }) => {};
  @override
  void batchRemoveSequence(MlxHandles handles, int batchHandle, int seqId) {}
  @override
  int batchActiveCount(MlxHandles handles, int batchHandle) => 0;
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
              systemPrompt: 'You are a test assistant.',
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

    test('reset allows new turn to run afterwards', () async {
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
      await iterator.moveNext(); // ready

      harness.handleMessage(
        const BrainRequest(type: BrainRequestType.reset).toJson(),
      );
      expect(runtime.resetCalls, 1);

      // After reset, a new turn should succeed without errors.
      harness.handleMessage(
        BrainRequest(
          type: BrainRequestType.runTurn,
          runTurn: _runTurnRequest(
            userMessage: const Message(role: Role.user, content: 'after reset'),
          ),
        ).toJson(),
      );

      fakeAgent.controller
        ..add(const AgentStepStarted(turnId: 'turn-2', step: 1))
        ..add(
          const AgentTurnFinished(
            turnId: 'turn-2',
            step: 1,
            finishReason: FinishReason.stop,
          ),
        );
      await fakeAgent.controller.close();

      final events = <AgentEvent>[];
      for (var i = 0; i < 2; i += 1) {
        await iterator.moveNext();
        events.add(
          AgentEvent.fromJson(
            Map<String, Object?>.from(iterator.current as Map),
          ),
        );
      }

      expect(events.first, isA<AgentStepStarted>());
      expect(events.last, isA<AgentTurnFinished>());
      await iterator.cancel();
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

    test('createSequence without payload emits error', () async {
      final receivePort = ReceivePort();

      BrainIsolateTestHarness(
        receivePort.sendPort,
        bundleFactory: _fakeBundleFactory,
      ).handleMessage(
        const BrainRequest(type: BrainRequestType.createSequence).toJson(),
      );

      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(await receivePort.first as Map),
      );
      expect(event, isA<AgentError>());
      expect(
        (event as AgentError).error,
        contains('CreateSequence payload'),
      );
      receivePort.close();
    });

    test('destroySequence without payload emits error', () async {
      final receivePort = ReceivePort();

      BrainIsolateTestHarness(
        receivePort.sendPort,
        bundleFactory: _fakeBundleFactory,
      ).handleMessage(
        const BrainRequest(type: BrainRequestType.destroySequence).toJson(),
      );

      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(await receivePort.first as Map),
      );
      expect(event, isA<AgentError>());
      expect(
        (event as AgentError).error,
        contains('DestroySequence payload'),
      );
      receivePort.close();
    });

    test('createSequence before init emits error', () async {
      final receivePort = ReceivePort();

      BrainIsolateTestHarness(
        receivePort.sendPort,
        bundleFactory: _fakeBundleFactory,
      ).handleMessage(
        const BrainRequest(
          type: BrainRequestType.createSequence,
          createSequence: CreateSequenceRequest(sequenceId: 1),
        ).toJson(),
      );

      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(await receivePort.first as Map),
      );
      expect(event, isA<AgentError>());
      expect((event as AgentError).error, contains('not initialized'));
      receivePort.close();
    });

    test('destroySequence before init emits error', () async {
      final receivePort = ReceivePort();

      BrainIsolateTestHarness(
        receivePort.sendPort,
        bundleFactory: _fakeBundleFactory,
      ).handleMessage(
        const BrainRequest(
          type: BrainRequestType.destroySequence,
          destroySequence: DestroySequenceRequest(sequenceId: 1),
        ).toJson(),
      );

      final event = AgentEvent.fromJson(
        Map<String, Object?>.from(await receivePort.first as Map),
      );
      expect(event, isA<AgentError>());
      expect((event as AgentError).error, contains('not initialized'));
      receivePort.close();
    });

    group('multi-sequence', () {
      late _FakeInferenceRuntime runtime;
      late ReceivePort receivePort;
      late StreamIterator<dynamic> iterator;
      late BrainIsolateTestHarness harness;

      setUp(() async {
        runtime = _FakeInferenceRuntime();
        receivePort = ReceivePort();
        iterator = StreamIterator(receivePort);
        harness =
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
                  }) => _agentLoopBundle(
                    runtime: runtime,
                    conversation: conversation,
                    tools: tools,
                    contextSize: contextSize,
                    maxOutputTokens: maxOutputTokens,
                  ),
            )..handleMessage(
              BrainRequest(
                type: BrainRequestType.init,
                init: _initRequest(),
              ).toJson(),
            );
        await iterator.moveNext(); // ready
      });

      tearDown(() async {
        await iterator.cancel();
        receivePort.close();
      });

      test('createSequence fresh creates new sequence', () {
        harness.handleMessage(
          const BrainRequest(
            type: BrainRequestType.createSequence,
            createSequence: CreateSequenceRequest(sequenceId: 1),
          ).toJson(),
        );

        expect(runtime.createSequenceCalls, 1);
        expect(runtime.lastCreatedSeqId, 1);
      });

      test('createSequence duplicate emits error', () async {
        harness
          ..handleMessage(
            const BrainRequest(
              type: BrainRequestType.createSequence,
              createSequence: CreateSequenceRequest(sequenceId: 1),
            ).toJson(),
          )
          ..handleMessage(
            const BrainRequest(
              type: BrainRequestType.createSequence,
              createSequence: CreateSequenceRequest(sequenceId: 1),
            ).toJson(),
          );

        await iterator.moveNext();
        final event = AgentEvent.fromJson(
          Map<String, Object?>.from(iterator.current as Map),
        );
        expect(event, isA<AgentError>());
        expect((event as AgentError).error, contains('already exists'));
      });

      test('createSequence with fork copies from source', () {
        harness.handleMessage(
          const BrainRequest(
            type: BrainRequestType.createSequence,
            createSequence: CreateSequenceRequest(
              sequenceId: 1,
              forkFrom: 0,
            ),
          ).toJson(),
        );

        expect(runtime.forkSequenceCalls, 1);
        expect(runtime.lastFork?.source, 0);
        expect(runtime.lastFork?.target, 1);
      });

      test('createSequence fork from non-existent emits error', () async {
        harness.handleMessage(
          const BrainRequest(
            type: BrainRequestType.createSequence,
            createSequence: CreateSequenceRequest(
              sequenceId: 1,
              forkFrom: 99,
            ),
          ).toJson(),
        );

        await iterator.moveNext();
        final event = AgentEvent.fromJson(
          Map<String, Object?>.from(iterator.current as Map),
        );
        expect(event, isA<AgentError>());
        expect((event as AgentError).error, contains('does not exist'));
      });

      test('createSequence with non-InferenceRuntime emits error', () async {
        // Use a harness with a plain _FakeRuntime (not InferenceRuntime).
        final plainPort = ReceivePort();
        final plainIterator = StreamIterator(plainPort);
        final plainHarness =
            BrainIsolateTestHarness(
              plainPort.sendPort,
              bundleFactory: _fakeBundleFactory,
            )..handleMessage(
              BrainRequest(
                type: BrainRequestType.init,
                init: _initRequest(),
              ).toJson(),
            );
        await plainIterator.moveNext(); // ready

        plainHarness.handleMessage(
          const BrainRequest(
            type: BrainRequestType.createSequence,
            createSequence: CreateSequenceRequest(sequenceId: 1),
          ).toJson(),
        );

        await plainIterator.moveNext();
        final event = AgentEvent.fromJson(
          Map<String, Object?>.from(plainIterator.current as Map),
        );
        expect(event, isA<AgentError>());
        expect(
          (event as AgentError).error,
          contains('does not support multi-sequence'),
        );
        await plainIterator.cancel();
        plainPort.close();
      });

      test('createSequence runtime error emits error', () async {
        runtime.throwOnCreate = true;

        harness.handleMessage(
          const BrainRequest(
            type: BrainRequestType.createSequence,
            createSequence: CreateSequenceRequest(sequenceId: 1),
          ).toJson(),
        );

        await iterator.moveNext();
        final event = AgentEvent.fromJson(
          Map<String, Object?>.from(iterator.current as Map),
        );
        expect(event, isA<AgentError>());
        expect((event as AgentError).error, contains('create failed'));
      });

      test('destroySequence removes sequence', () {
        harness
          ..handleMessage(
            const BrainRequest(
              type: BrainRequestType.createSequence,
              createSequence: CreateSequenceRequest(sequenceId: 1),
            ).toJson(),
          )
          ..handleMessage(
            const BrainRequest(
              type: BrainRequestType.destroySequence,
              destroySequence: DestroySequenceRequest(sequenceId: 1),
            ).toJson(),
          );

        expect(runtime.destroySequenceCalls, 1);
        expect(runtime.lastDestroyedSeqId, 1);
      });

      test('destroySequence 0 emits error', () async {
        harness.handleMessage(
          const BrainRequest(
            type: BrainRequestType.destroySequence,
            destroySequence: DestroySequenceRequest(sequenceId: 0),
          ).toJson(),
        );

        await iterator.moveNext();
        final event = AgentEvent.fromJson(
          Map<String, Object?>.from(iterator.current as Map),
        );
        expect(event, isA<AgentError>());
        expect(
          (event as AgentError).error,
          contains('Cannot destroy sequence 0'),
        );
      });

      test('destroySequence non-existent emits error', () async {
        harness.handleMessage(
          const BrainRequest(
            type: BrainRequestType.destroySequence,
            destroySequence: DestroySequenceRequest(sequenceId: 99),
          ).toJson(),
        );

        await iterator.moveNext();
        final event = AgentEvent.fromJson(
          Map<String, Object?>.from(iterator.current as Map),
        );
        expect(event, isA<AgentError>());
        expect((event as AgentError).error, contains('does not exist'));
      });

      test('destroySequence runtime error emits error', () async {
        runtime.throwOnDestroy = true;

        harness
          ..handleMessage(
            const BrainRequest(
              type: BrainRequestType.createSequence,
              createSequence: CreateSequenceRequest(sequenceId: 1),
            ).toJson(),
          )
          ..handleMessage(
            const BrainRequest(
              type: BrainRequestType.destroySequence,
              destroySequence: DestroySequenceRequest(sequenceId: 1),
            ).toJson(),
          );

        await iterator.moveNext();
        final event = AgentEvent.fromJson(
          Map<String, Object?>.from(iterator.current as Map),
        );
        expect(event, isA<AgentError>());
        expect((event as AgentError).error, contains('destroy failed'));
      });

      test('createSequence during active turn works', () async {
        final turnPort = ReceivePort();
        final turnIterator = StreamIterator(turnPort);
        final turnHarness =
            BrainIsolateTestHarness(
              turnPort.sendPort,
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
                  }) => (
                    agent: _FakeAgentRunner(
                      contextSize: contextSize,
                      maxOutputTokens: maxOutputTokens,
                    ),
                    conversation: conversation,
                    llm: _FakeLlmAdapter(),
                    tools: tools,
                    context: _FakeContextManager(),
                    runtime: _FakeInferenceRuntime(),
                  ),
            )..handleMessage(
              BrainRequest(
                type: BrainRequestType.init,
                init: _initRequest(),
              ).toJson(),
            );
        await turnIterator.moveNext(); // ready

        // Start a turn to get into TurnActiveState, then create sequence.
        turnHarness
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
              type: BrainRequestType.createSequence,
              createSequence: CreateSequenceRequest(sequenceId: 1),
            ).toJson(),
          );

        // Destroy should fail because runtime is not InferenceRuntime,
        // but createSequence output is fired (exercises TurnActiveState
        // CreateSequenceInput handler).
        await turnIterator.moveNext();
        final event = AgentEvent.fromJson(
          Map<String, Object?>.from(turnIterator.current as Map),
        );
        expect(event, isA<AgentError>());
        expect(
          (event as AgentError).error,
          contains('Cannot create agent loop for sequence 1'),
        );

        await turnIterator.cancel();
        turnPort.close();
      });

      test(
        'destroySequence during active turn on that seq emits error',
        () async {
          final turnPort = ReceivePort();
          final turnIterator = StreamIterator(turnPort);
          final turnHarness =
              BrainIsolateTestHarness(
                turnPort.sendPort,
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
                    }) => _agentLoopBundle(
                      runtime: _FakeInferenceRuntime(),
                      conversation: conversation,
                      tools: tools,
                      contextSize: contextSize,
                      maxOutputTokens: maxOutputTokens,
                    ),
              )..handleMessage(
                BrainRequest(
                  type: BrainRequestType.init,
                  init: _initRequest(),
                ).toJson(),
              );
          await turnIterator.moveNext(); // ready

          // Start a turn on sequence 0 then try to destroy it.
          turnHarness
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
                type: BrainRequestType.destroySequence,
                destroySequence: DestroySequenceRequest(sequenceId: 0),
              ).toJson(),
            );

          await turnIterator.moveNext();
          final event = AgentEvent.fromJson(
            Map<String, Object?>.from(turnIterator.current as Map),
          );
          expect(event, isA<AgentError>());
          expect(
            (event as AgentError).error,
            contains('while turn is active'),
          );

          await turnIterator.cancel();
          turnPort.close();
        },
      );

      test('run_turn on non-existent sequence emits error', () async {
        harness.handleMessage(
          const BrainRequest(
            type: BrainRequestType.runTurn,
            runTurn: RunTurnRequest(
              sequenceId: 99,
              userMessage: Message(role: Role.user, content: 'hi'),
              settings: _defaultSettings,
              enableReasoning: true,
            ),
          ).toJson(),
        );

        await iterator.moveNext();
        final event = AgentEvent.fromJson(
          Map<String, Object?>.from(iterator.current as Map),
        );
        expect(event, isA<AgentError>());
        expect(
          (event as AgentError).error,
          contains('does not exist'),
        );
      });

      test('concurrent turns on different sequences', () async {
        // Create sequence 1, then start turns on seq 0 and seq 1
        // synchronously. First runTurn transitions Idle → TurnActive.
        // Second runTurn hits TurnActiveState.RunTurnInput for seq 1
        // (the concurrent turn path: lines 208-220).
        harness
          ..handleMessage(
            const BrainRequest(
              type: BrainRequestType.createSequence,
              createSequence: CreateSequenceRequest(sequenceId: 1),
            ).toJson(),
          )
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
              type: BrainRequestType.runTurn,
              runTurn: RunTurnRequest(
                sequenceId: 1,
                userMessage: Message(role: Role.user, content: 'hey'),
                settings: _defaultSettings,
                enableReasoning: true,
              ),
            ).toJson(),
          );

        // Both turns complete asynchronously (Stream.empty from
        // _FakeInferenceRuntime). The first TurnCompleted fires toSelf()
        // (line 254) because the other sequence is still active. The second
        // TurnCompleted transitions to IdleState.
        // Drain all events emitted.
        final events = <AgentEvent>[];
        while (await iterator.moveNext()) {
          final raw = iterator.current;
          if (raw is! Map) continue;
          final event = AgentEvent.fromJson(
            Map<String, Object?>.from(raw),
          );
          events.add(event);
          // Both turns should finish.
          final finished = events.whereType<AgentTurnFinished>().length;
          if (finished >= 2) break;
        }

        expect(
          events.whereType<AgentTurnFinished>().length,
          greaterThanOrEqualTo(2),
        );
      });

      test('concurrent turn rejects non-user message', () async {
        // Start turn on seq 0, create seq 1, then send a non-user message
        // on seq 1 while in TurnActiveState.
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
              type: BrainRequestType.createSequence,
              createSequence: CreateSequenceRequest(sequenceId: 1),
            ).toJson(),
          )
          ..handleMessage(
            const BrainRequest(
              type: BrainRequestType.runTurn,
              runTurn: RunTurnRequest(
                sequenceId: 1,
                userMessage: Message(role: Role.assistant, content: 'oops'),
                settings: _defaultSettings,
                enableReasoning: true,
              ),
            ).toJson(),
          );

        await iterator.moveNext();
        final event = AgentEvent.fromJson(
          Map<String, Object?>.from(iterator.current as Map),
        );
        expect(event, isA<AgentError>());
        expect(
          (event as AgentError).error,
          contains('requires a user message'),
        );
      });

      test('turnFailed with other sequences still active', () async {
        // Start a turn on seq 0 (enters TurnActiveState), then start a
        // turn on non-existent seq 99. The logic adds 99 to activeSequences
        // and fires StreamTurnRequested(99). _streamTurn(99) finds no agent
        // and fires TurnFailed(99) while seq 0 is still active — exercising
        // the toSelf() branch (line 263).
        final gate = Completer<void>();
        runtime.generateGates[0] = gate;

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
              type: BrainRequestType.runTurn,
              runTurn: RunTurnRequest(
                sequenceId: 99,
                userMessage: Message(role: Role.user, content: 'hey'),
                settings: _defaultSettings,
                enableReasoning: true,
              ),
            ).toJson(),
          );

        // Seq 99 fails immediately (no agent), emitting an error while
        // seq 0 is still active.
        await iterator.moveNext();
        final event = AgentEvent.fromJson(
          Map<String, Object?>.from(iterator.current as Map),
        );
        expect(event, isA<AgentError>());
        expect(
          (event as AgentError).error,
          contains('does not exist'),
        );

        // Release gate so seq 0 completes and we can tear down cleanly.
        gate.complete();
      });

      test('destroySequence on non-active seq during active turn', () async {
        // Create seq 1, start turn on seq 0, then destroy seq 1 (not active).
        harness
          ..handleMessage(
            const BrainRequest(
              type: BrainRequestType.createSequence,
              createSequence: CreateSequenceRequest(sequenceId: 1),
            ).toJson(),
          )
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
              type: BrainRequestType.destroySequence,
              destroySequence: DestroySequenceRequest(sequenceId: 1),
            ).toJson(),
          );

        // Destroy should succeed (seq 1 not active).
        expect(runtime.destroySequenceCalls, 1);
        expect(runtime.lastDestroyedSeqId, 1);
      });
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
    systemPrompt: 'You are a test assistant.',
  );
}

RunTurnRequest _runTurnRequest({required Message userMessage}) {
  return RunTurnRequest(
    userMessage: userMessage,
    settings: _defaultSettings,
    enableReasoning: true,
  );
}
