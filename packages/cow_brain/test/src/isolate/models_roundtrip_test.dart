import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

void main() {
  group('Isolate models roundtrip', () {
    test('message and tool models roundtrip', () {
      final call = ToolCall(
        id: StringBuffer('call-1').toString(),
        name: 'search',
        arguments: <String, Object?>{
          'q': StringBuffer('cows').toString(),
        },
      );
      final message = Message(
        role: Role.assistant,
        content: StringBuffer('Hello').toString(),
        reasoningContent: StringBuffer('Thinking').toString(),
        toolCalls: <ToolCall>[call],
        toolCallId: StringBuffer('tool-1').toString(),
        name: StringBuffer('assistant').toString(),
      );
      final definition = ToolDefinition(
        name: StringBuffer('search').toString(),
        description: StringBuffer('Search the web').toString(),
        parameters: <String, Object?>{
          'type': StringBuffer('object').toString(),
        },
      );
      final result = ToolResult(
        toolCallId: StringBuffer('call-1').toString(),
        name: StringBuffer('search').toString(),
        content: StringBuffer('ok').toString(),
        isError: true,
        errorMessage: StringBuffer('oops').toString(),
      );

      expect(Message.fromJson(message.toJson()).content, 'Hello');
      expect(ToolDefinition.fromJson(definition.toJson()).name, 'search');
      expect(ToolCall.fromJson(call.toJson()).arguments['q'], 'cows');
      final decoded = ToolResult.fromJson(result.toJson());
      expect(decoded.isError, isTrue);
      expect(decoded.errorMessage, 'oops');
    });

    test('MlxRuntimeOptions roundtrip', () {
      final mlxOptions = MlxRuntimeOptions(
        modelPath: StringBuffer('/models/mlx-model').toString(),
        libraryPath: StringBuffer('/lib/libmlx.dylib').toString(),
        contextSize: int.parse('4096'),
        samplingOptions: SamplingOptions(
          seed: int.parse('7'),
          topK: int.parse('40'),
          topP: 0.95,
          temperature: 0.8,
        ),
        maxOutputTokensDefault: int.parse('1024'),
      );

      final decoded = MlxRuntimeOptions.fromJson(mlxOptions.toJson());
      expect(decoded.modelPath, '/models/mlx-model');
      expect(decoded.libraryPath, '/lib/libmlx.dylib');
      expect(decoded.contextSize, 4096);
      expect(decoded.maxOutputTokensDefault, 1024);
      expect(decoded.samplingOptions.topK, 40);
      expect(decoded.backend, InferenceBackend.mlx);
    });

    test('BackendRuntimeOptions.fromJson dispatches MLX branch', () {
      const mlxOptions = MlxRuntimeOptions(
        modelPath: '/models/mlx-model',
        libraryPath: '/lib/libmlx.dylib',
        contextSize: 2048,
      );

      final decoded = BackendRuntimeOptions.fromJson(mlxOptions.toJson());
      expect(decoded, isA<MlxRuntimeOptions>());
      expect((decoded as MlxRuntimeOptions).contextSize, 2048);
    });

    test('configs and options roundtrip', () {
      final modelOptions = LlamaModelOptions(
        nGpuLayers: int.parse('8'),
        mainGpu: int.parse('1'),
        numa: int.parse('2'),
        useMmap: true,
        useMlock: false,
        checkTensors: true,
      );
      final contextOptions = LlamaContextOptions(
        contextSize: int.parse('2048'),
        nBatch: int.parse('64'),
        nThreads: int.parse('4'),
        nThreadsBatch: int.parse('2'),
        useFlashAttn: true,
      );
      final samplingOptions = SamplingOptions(
        seed: int.parse('42'),
        topK: int.parse('30'),
        topP: 0.9,
        minP: 0.1,
        temperature: 0.7,
        typicalP: 0.8,
        penaltyRepeat: 1.1,
        penaltyLastN: int.parse('64'),
      );
      final runtime = LlamaCppRuntimeOptions(
        modelPath: StringBuffer('/models/qwen.gguf').toString(),
        contextOptions: contextOptions,
        modelOptions: modelOptions,
        samplingOptions: samplingOptions,
        maxOutputTokensDefault: int.parse('256'),
        libraryPath: StringBuffer('/libllama.dylib').toString(),
      );
      final config = LlmConfig(
        requiresReset: false,
        reusePrefixMessageCount: int.parse('1'),
      );
      final settings = AgentSettings(
        safetyMarginTokens: int.parse('10'),
        maxSteps: int.parse('3'),
      );

      expect(LlamaModelOptions.fromJson(modelOptions.toJson()).nGpuLayers, 8);
      expect(
        LlamaContextOptions.fromJson(contextOptions.toJson()).useFlashAttn,
        isTrue,
      );
      expect(SamplingOptions.fromJson(samplingOptions.toJson()).topK, 30);
      expect(
        LlamaCppRuntimeOptions.fromJson(runtime.toJson()).libraryPath,
        '/libllama.dylib',
      );
      expect(LlmConfig.fromJson(config.toJson()).reusePrefixMessageCount, 1);
      expect(AgentSettings.fromJson(settings.toJson()).maxSteps, 3);
    });

    test('requests roundtrip and default enum handling', () {
      final init = InitRequest(
        modelHandle: 1,
        options: LlamaCppRuntimeOptions(
          modelPath: StringBuffer('/models/qwen.gguf').toString(),
          libraryPath: '/tmp/libllama.so',
          contextOptions: LlamaContextOptions(
            contextSize: int.parse('2048'),
            nBatch: int.parse('64'),
            nThreads: int.parse('4'),
            nThreadsBatch: int.parse('2'),
          ),
        ),
        profile: ModelProfileId.qwen25,
        tools: [
          ToolDefinition(
            name: StringBuffer('search').toString(),
            description: StringBuffer('Search').toString(),
            parameters: <String, Object?>{},
          ),
        ],
        settings: AgentSettings(
          safetyMarginTokens: int.parse('10'),
          maxSteps: int.parse('3'),
        ),
        enableReasoning: true,
      );

      final initDecoded = InitRequest.fromJson(init.toJson());
      expect(initDecoded.profile, ModelProfileId.qwen25);

      final unknownJson = init.toJson()..['profile'] = 'unknown';
      final unknownDecoded = InitRequest.fromJson(unknownJson);
      expect(unknownDecoded.profile, ModelProfileId.qwen3);

      final runTurn = RunTurnRequest(
        userMessage: Message(
          role: Role.user,
          content: StringBuffer('Hi').toString(),
        ),
        settings: AgentSettings(
          safetyMarginTokens: int.parse('4'),
          maxSteps: int.parse('2'),
        ),
        enableReasoning: false,
      );
      final toolResult = ToolResultRequest(
        turnId: StringBuffer('turn-1').toString(),
        toolResult: ToolResult(
          toolCallId: StringBuffer('call-1').toString(),
          name: StringBuffer('search').toString(),
          content: StringBuffer('ok').toString(),
        ),
      );
      final cancel = CancelRequest(
        turnId: StringBuffer('turn-1').toString(),
      );

      expect(
        RunTurnRequest.fromJson(runTurn.toJson()).userMessage.content,
        'Hi',
      );
      expect(ToolResultRequest.fromJson(toolResult.toJson()).turnId, 'turn-1');
      expect(CancelRequest.fromJson(cancel.toJson()).turnId, 'turn-1');

      const reset = BrainRequest(type: BrainRequestType.reset);
      const dispose = BrainRequest(type: BrainRequestType.dispose);
      final initRequest = BrainRequest(
        type: BrainRequestType.init,
        init: init,
      );
      final runTurnRequest = BrainRequest(
        type: BrainRequestType.runTurn,
        runTurn: runTurn,
      );
      final toolResultRequest = BrainRequest(
        type: BrainRequestType.toolResult,
        toolResult: toolResult,
      );
      final cancelRequest = BrainRequest(
        type: BrainRequestType.cancel,
        cancel: cancel,
      );

      expect(
        BrainRequest.fromJson(reset.toJson()).type,
        BrainRequestType.reset,
      );
      expect(
        BrainRequest.fromJson(dispose.toJson()).type,
        BrainRequestType.dispose,
      );
      expect(
        BrainRequest.fromJson(initRequest.toJson()).init?.profile,
        ModelProfileId.qwen25,
      );
      expect(
        BrainRequest.fromJson(
          runTurnRequest.toJson(),
        ).runTurn?.userMessage.content,
        'Hi',
      );
      expect(
        BrainRequest.fromJson(toolResultRequest.toJson()).toolResult?.turnId,
        'turn-1',
      );
      expect(
        BrainRequest.fromJson(cancelRequest.toJson()).cancel?.turnId,
        'turn-1',
      );
    });

    test('agent events roundtrip', () {
      final events = <AgentEvent>[
        const AgentReady(),
        AgentStepStarted(
          turnId: StringBuffer('turn-1').toString(),
          step: int.parse('1'),
        ),
        AgentContextTrimmed(
          turnId: StringBuffer('turn-1').toString(),
          step: int.parse('1'),
          droppedMessageCount: int.parse('2'),
        ),
        AgentTelemetryUpdate(
          turnId: StringBuffer('turn-1').toString(),
          step: int.parse('1'),
          promptTokens: int.parse('10'),
          budgetTokens: int.parse('20'),
          remainingTokens: int.parse('10'),
          contextSize: int.parse('128'),
          maxOutputTokens: int.parse('32'),
          safetyMarginTokens: int.parse('4'),
        ),
        AgentTextDelta(
          turnId: StringBuffer('turn-1').toString(),
          step: int.parse('1'),
          text: StringBuffer('hi').toString(),
        ),
        AgentReasoningDelta(
          turnId: StringBuffer('turn-1').toString(),
          step: int.parse('1'),
          text: StringBuffer('think').toString(),
        ),
        AgentToolCalls(
          turnId: StringBuffer('turn-1').toString(),
          step: int.parse('1'),
          calls: [
            ToolCall(
              id: StringBuffer('call-1').toString(),
              name: StringBuffer('search').toString(),
              arguments: <String, Object?>{
                'q': StringBuffer('cows').toString(),
              },
            ),
          ],
          finishReason: FinishReason.toolCalls,
          preToolText: StringBuffer('pre').toString(),
          preToolReasoning: StringBuffer('why').toString(),
        ),
        AgentToolResult(
          turnId: StringBuffer('turn-1').toString(),
          step: int.parse('1'),
          result: ToolResult(
            toolCallId: StringBuffer('call-1').toString(),
            name: StringBuffer('search').toString(),
            content: StringBuffer('ok').toString(),
          ),
        ),
        AgentStepFinished(
          turnId: StringBuffer('turn-1').toString(),
          step: int.parse('1'),
          text: StringBuffer('done').toString(),
          finishReason: FinishReason.stop,
          reasoning: StringBuffer('why').toString(),
        ),
        AgentTurnFinished(
          turnId: StringBuffer('turn-1').toString(),
          step: int.parse('1'),
          finishReason: FinishReason.stop,
        ),
        AgentError(
          error: StringBuffer('boom').toString(),
          turnId: StringBuffer('turn-1').toString(),
          step: int.parse('1'),
        ),
      ];

      for (final event in events) {
        final decoded = AgentEvent.fromJson(event.toJson());
        expect(decoded.type, event.type);
      }
    });
  });
}
