import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

const _runtimeOptions = LlamaRuntimeOptions(
  modelPath: '/tmp/model.gguf',
  contextOptions: LlamaContextOptions(
    contextSize: 2048,
    nBatch: 64,
    nThreads: 8,
    nThreadsBatch: 8,
  ),
);

const _settings = AgentSettings(
  safetyMarginTokens: 64,
  maxSteps: 8,
);

void main() {
  group('BrainRequest JSON', () {
    test('init roundtrip preserves settings and tools', () {
      const request = BrainRequest(
        type: BrainRequestType.init,
        init: InitRequest(
          runtimeOptions: _runtimeOptions,
          profile: LlamaProfileId.qwen3,
          tools: [
            ToolDefinition(
              name: 'search',
              description: 'Search',
              parameters: {'type': 'object'},
            ),
          ],
          settings: _settings,
          enableReasoning: true,
        ),
      );

      final json = request.toJson();
      final decoded = BrainRequest.fromJson(json);

      expect(decoded.type, BrainRequestType.init);
      expect(decoded.init, isNotNull);
      expect(decoded.init!.settings.maxSteps, 8);
      expect(decoded.init!.enableReasoning, isTrue);
      expect(decoded.init!.tools, hasLength(1));
      expect(decoded.init!.runtimeOptions.modelPath, '/tmp/model.gguf');
    });

    test('init roundtrip preserves profile ids', () {
      const request = BrainRequest(
        type: BrainRequestType.init,
        init: InitRequest(
          runtimeOptions: _runtimeOptions,
          profile: LlamaProfileId.qwen25,
          tools: <ToolDefinition>[],
          settings: _settings,
          enableReasoning: false,
        ),
      );

      final json = request.toJson();
      final decoded = BrainRequest.fromJson(json);

      expect(decoded.init!.profile, LlamaProfileId.qwen25);
    });

    test('run_turn roundtrip preserves settings', () {
      const request = BrainRequest(
        type: BrainRequestType.runTurn,
        runTurn: RunTurnRequest(
          userMessage: Message(role: Role.user, content: 'hello'),
          settings: _settings,
          enableReasoning: true,
        ),
      );

      final json = request.toJson();
      final decoded = BrainRequest.fromJson(json);

      expect(decoded.type, BrainRequestType.runTurn);
      expect(decoded.runTurn, isNotNull);
      expect(decoded.runTurn!.settings.maxSteps, 8);
      expect(decoded.runTurn!.enableReasoning, isTrue);
      expect(decoded.runTurn!.userMessage.content, 'hello');
    });

    test('tool_result roundtrip', () {
      const request = BrainRequest(
        type: BrainRequestType.toolResult,
        toolResult: ToolResultRequest(
          turnId: 'turn-1',
          toolResult: ToolResult(
            toolCallId: 'call-1',
            name: 'search',
            content: 'ok',
          ),
        ),
      );

      final json = request.toJson();
      final decoded = BrainRequest.fromJson(json);

      expect(decoded.type, BrainRequestType.toolResult);
      expect(decoded.toolResult!.turnId, 'turn-1');
      expect(decoded.toolResult!.toolResult.name, 'search');
    });

    test('cancel/reset/dispose roundtrip', () {
      const cancel = BrainRequest(
        type: BrainRequestType.cancel,
        cancel: CancelRequest(turnId: 'turn-9'),
      );
      const reset = BrainRequest(type: BrainRequestType.reset);
      const dispose = BrainRequest(type: BrainRequestType.dispose);

      expect(BrainRequest.fromJson(cancel.toJson()).cancel!.turnId, 'turn-9');
      expect(
        BrainRequest.fromJson(reset.toJson()).type,
        BrainRequestType.reset,
      );
      expect(
        BrainRequest.fromJson(dispose.toJson()).type,
        BrainRequestType.dispose,
      );
    });
  });

  group('AgentEvent JSON', () {
    test('ready roundtrip exposes null turn metadata', () {
      const event = AgentReady();
      final decoded = AgentEvent.fromJson(event.toJson());

      expect(decoded, isA<AgentReady>());
      expect(decoded.turnId, isNull);
      expect(decoded.step, isNull);
    });

    test('text delta roundtrip', () {
      const event = AgentTextDelta(
        turnId: 'turn-1',
        step: 1,
        text: 'hi',
      );

      final json = event.toJson();
      final decoded = AgentEvent.fromJson(json);

      expect(decoded, isA<AgentTextDelta>());
      expect(decoded.type, AgentEventType.textDelta);
      expect(decoded.turnId, 'turn-1');
      expect(decoded.step, 1);
      expect((decoded as AgentTextDelta).text, 'hi');
    });

    test('tool calls roundtrip', () {
      const event = AgentToolCalls(
        turnId: 'turn-2',
        step: 3,
        calls: [
          ToolCall(id: 'call-1', name: 'search', arguments: {'q': 'cows'}),
        ],
        finishReason: FinishReason.toolCalls,
        preToolText: 'thinking',
      );

      final decoded = AgentEvent.fromJson(event.toJson());

      expect(decoded, isA<AgentToolCalls>());
      final toolCalls = decoded as AgentToolCalls;
      expect(toolCalls.calls.single.name, 'search');
      expect(toolCalls.preToolText, 'thinking');
      expect(toolCalls.finishReason, FinishReason.toolCalls);
    });

    test('context trimmed roundtrip', () {
      const event = AgentContextTrimmed(
        turnId: 'turn-3',
        step: 2,
        droppedMessageCount: 4,
      );

      final decoded = AgentEvent.fromJson(event.toJson());
      expect(decoded, isA<AgentContextTrimmed>());
      expect(decoded.turnId, 'turn-3');
      expect(decoded.step, 2);
    });

    test('telemetry update roundtrip', () {
      const event = AgentTelemetryUpdate(
        turnId: 'turn-4',
        step: 1,
        promptTokens: 120,
        budgetTokens: 256,
        remainingTokens: 136,
        contextSize: 512,
        maxOutputTokens: 64,
        safetyMarginTokens: 72,
      );

      final decoded = AgentEvent.fromJson(event.toJson());
      expect(decoded, isA<AgentTelemetryUpdate>());
      final telemetry = decoded as AgentTelemetryUpdate;
      expect(telemetry.turnId, 'turn-4');
      expect(telemetry.step, 1);
      expect(telemetry.promptTokens, 120);
      expect(telemetry.budgetTokens, 256);
      expect(telemetry.remainingTokens, 136);
      expect(telemetry.contextSize, 512);
      expect(telemetry.maxOutputTokens, 64);
      expect(telemetry.safetyMarginTokens, 72);
    });

    test('reasoning delta roundtrip', () {
      const event = AgentReasoningDelta(
        turnId: 'turn-4',
        step: 1,
        text: 'thinking',
      );

      final decoded = AgentEvent.fromJson(event.toJson());
      expect(decoded, isA<AgentReasoningDelta>());
      expect((decoded as AgentReasoningDelta).text, 'thinking');
    });

    test('tool result roundtrip', () {
      const event = AgentToolResult(
        turnId: 'turn-5',
        step: 1,
        result: ToolResult(
          toolCallId: 'call-1',
          name: 'search',
          content: 'ok',
        ),
      );

      final decoded = AgentEvent.fromJson(event.toJson());
      expect(decoded, isA<AgentToolResult>());
      expect((decoded as AgentToolResult).result.content, 'ok');
    });

    test('step finished roundtrip', () {
      const event = AgentStepFinished(
        turnId: 'turn-6',
        step: 2,
        text: 'done',
        finishReason: FinishReason.stop,
        reasoning: 'why not',
      );

      final decoded = AgentEvent.fromJson(event.toJson());
      expect(decoded, isA<AgentStepFinished>());
      expect((decoded as AgentStepFinished).reasoning, 'why not');
    });

    test('error roundtrip without turn metadata', () {
      const event = AgentError(error: 'boom');
      final decoded = AgentEvent.fromJson(event.toJson());

      expect(decoded, isA<AgentError>());
      expect(decoded.turnId, isNull);
      expect(decoded.step, isNull);
      expect((decoded as AgentError).error, 'boom');
    });
  });

  group('Model JSON', () {
    test('llm config roundtrip', () {
      const config = LlmConfig(
        requiresReset: true,
        reusePrefixMessageCount: 3,
      );

      final decoded = LlmConfig.fromJson(config.toJson());
      expect(decoded.requiresReset, isTrue);
      expect(decoded.reusePrefixMessageCount, 3);
    });
  });
}
