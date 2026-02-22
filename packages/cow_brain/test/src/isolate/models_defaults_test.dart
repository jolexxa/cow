import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

void main() {
  group('Models defaults and accessors', () {
    test('message and tool defaults', () {
      final call = ToolCall(
        id: StringBuffer('call-1').toString(),
        name: StringBuffer('search').toString(),
        arguments: <String, Object?>{'q': 'hi'},
      );
      final message = Message(
        role: Role.user,
        content: StringBuffer('hello').toString(),
        reasoningContent: StringBuffer('thinking').toString(),
        toolCalls: <ToolCall>[call],
        toolCallId: StringBuffer('tool-1').toString(),
        name: StringBuffer('alice').toString(),
      );
      final definition = ToolDefinition(
        name: StringBuffer('search').toString(),
        description: StringBuffer('Search').toString(),
        parameters: <String, Object?>{'type': 'object'},
      );
      final result = ToolResult(
        toolCallId: StringBuffer('call-1').toString(),
        name: StringBuffer('search').toString(),
        content: StringBuffer('ok').toString(),
      );
      expect(message.role, Role.user);
      expect(message.content, 'hello');
      expect(message.reasoningContent, 'thinking');
      expect(message.toolCalls, isNotEmpty);
      expect(message.name, 'alice');
      expect(message.toolCallId, 'tool-1');
      expect(message.toolCalls.single.name, 'search');
      expect(definition.name, 'search');
      expect(definition.description, 'Search');
      expect(definition.parameters['type'], 'object');
      expect(result.toolCallId, 'call-1');
      expect(result.name, 'search');
      expect(result.content, 'ok');
      expect(result.isError, isFalse);
      expect(result.errorMessage, isNull);
    });

    test('runtime options provide defaults', () {
      const contextOptions = LlamaContextOptions(
        contextSize: 2048,
        nBatch: 64,
        nThreads: 8,
        nThreadsBatch: 4,
      );
      final runtime = LlamaCppRuntimeOptions(
        modelPath: StringBuffer('/models/qwen.gguf').toString(),
        libraryPath: '/tmp/libllama.so',
        contextOptions: contextOptions,
      );

      expect(runtime.maxOutputTokensDefault, 512);
      expect(runtime.libraryPath, '/tmp/libllama.so');
      expect(runtime.contextOptions.contextSize, 2048);
      expect(runtime.contextOptions.nThreads, 8);
      expect(runtime.modelOptions.useMlock, isNull);
      expect(runtime.samplingOptions.seed, 0);
    });

    test('model, context, and sampling option accessors', () {
      const modelOptions = LlamaModelOptions();
      const samplingOptions = SamplingOptions();
      const contextOptions = LlamaContextOptions(
        contextSize: 128,
        nBatch: 16,
        nThreads: 2,
        nThreadsBatch: 2,
        useFlashAttn: true,
      );

      expect(modelOptions.nGpuLayers, isNull);
      expect(modelOptions.useMmap, isNull);
      expect(modelOptions.checkTensors, isNull);
      expect(samplingOptions.seed, 0);
      expect(samplingOptions.topK, isNull);
      expect(samplingOptions.penaltyLastN, isNull);
      expect(samplingOptions.typicalP, isNull);
      expect(contextOptions.useFlashAttn, isTrue);
    });

    test('agent events expose required fields', () {
      final events = <AgentEvent>[
        const AgentReady(),
        const AgentStepStarted(turnId: 't1', step: 1),
        const AgentContextTrimmed(
          turnId: 't1',
          step: 2,
          droppedMessageCount: 1,
        ),
        const AgentTelemetryUpdate(
          turnId: 't1',
          step: 2,
          promptTokens: 10,
          budgetTokens: 20,
          remainingTokens: 5,
          contextSize: 128,
          maxOutputTokens: 32,
          safetyMarginTokens: 4,
        ),
        const AgentTextDelta(turnId: 't1', step: 3, text: 'hi'),
        const AgentReasoningDelta(turnId: 't1', step: 3, text: 'why'),
        const AgentToolCalls(
          turnId: 't1',
          step: 4,
          calls: [
            ToolCall(id: 'call-1', name: 'search', arguments: {'q': 'cow'}),
          ],
          finishReason: FinishReason.toolCalls,
        ),
        const AgentToolResult(
          turnId: 't1',
          step: 4,
          result: ToolResult(
            toolCallId: 'call-1',
            name: 'search',
            content: 'ok',
          ),
        ),
        const AgentStepFinished(
          turnId: 't1',
          step: 5,
          text: 'done',
          finishReason: FinishReason.stop,
        ),
        const AgentTurnFinished(
          turnId: 't1',
          step: 5,
          finishReason: FinishReason.stop,
        ),
        const AgentError(error: 'boom'),
      ];

      expect(events.first.type, AgentEventType.ready);
      expect(events.first.turnId, isNull);
      expect(events.first.step, isNull);
      expect(events[1].turnId, 't1');
      expect(events[1].step, 1);
      expect(events[2].step, 2);
      expect(events[3].turnId, 't1');
      expect(events[4].type, AgentEventType.textDelta);
      expect(events[5].type, AgentEventType.reasoningDelta);
      expect(events[6].type, AgentEventType.toolCalls);
      expect(events[7].type, AgentEventType.toolResult);
      expect(events[8].type, AgentEventType.stepFinished);
      expect(events[9].type, AgentEventType.turnFinished);
      expect(events.last.turnId, isNull);
    });
  });
}
