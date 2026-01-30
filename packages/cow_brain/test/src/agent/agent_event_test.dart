import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

void main() {
  group('AgentEvent', () {
    test('events carry turnId and step metadata', () {
      const event = AgentTextDelta(
        turnId: 'turn-1',
        step: 2,
        text: 'hi',
      );

      expect(event.turnId, 'turn-1');
      expect(event.step, 2);
      expect(event.text, 'hi');
    });

    test(
      'tool-call finish event holds tool calls and optional pre-tool text',
      () {
        const calls = [
          ToolCall(id: '1', name: 'search', arguments: {}),
        ];

        const event = AgentToolCalls(
          turnId: 'turn-1',
          step: 1,
          calls: calls,
          finishReason: FinishReason.toolCalls,
          preToolText: 'thinking',
        );

        expect(event.calls, calls);
        expect(event.finishReason, FinishReason.toolCalls);
        expect(event.preToolText, 'thinking');
      },
    );

    test('covers reasoning, context trimmed, and failure events', () {
      const reasoning = AgentReasoningDelta(
        turnId: 'turn-2',
        step: 1,
        text: 'plan',
      );
      const trimmed = AgentContextTrimmed(
        turnId: 'turn-2',
        step: 1,
        droppedMessageCount: 2,
      );
      const failed = AgentError(
        turnId: 'turn-2',
        step: 1,
        error: 'boom',
      );
      const cancelled = AgentTurnFinished(
        turnId: 'turn-2',
        step: 1,
        finishReason: FinishReason.cancelled,
      );

      expect(reasoning.text, 'plan');
      expect(trimmed.droppedMessageCount, 2);
      expect(failed.error, 'boom');
      expect(cancelled.turnId, 'turn-2');
      expect(cancelled.finishReason, FinishReason.cancelled);
    });
  });
}
