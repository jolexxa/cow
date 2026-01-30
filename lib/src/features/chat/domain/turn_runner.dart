import 'package:cow/src/features/chat/domain/active_turn.dart';
import 'package:cow_brain/cow_brain.dart';

final class TurnRunner {
  TurnRunner(this.turn);

  final ActiveTurn turn;

  bool handle(AgentEvent event) {
    return switch (event) {
      AgentTextDelta(:final text) => _onTextDelta(text),
      AgentReasoningDelta(:final text) => _onReasoningDelta(text),
      AgentContextTrimmed(:final droppedMessageCount) => _onContextTrimmed(
        droppedMessageCount,
      ),
      AgentToolCalls(:final calls) => _onToolCalls(calls),
      AgentToolResult(:final result) => _onToolResult(result),
      AgentError(:final error) => throw Exception(error),
      AgentStepFinished() ||
      AgentTurnFinished() ||
      AgentStepStarted() ||
      AgentReady() => false,
      AgentTelemetryUpdate() => false,
    };
  }

  bool _onTextDelta(String text) {
    if (text.isEmpty) {
      return false;
    }
    turn.appendAssistant(text);
    return true;
  }

  bool _onReasoningDelta(String text) {
    if (text.isEmpty) {
      return false;
    }
    turn.appendReasoning(text);
    return true;
  }

  bool _onContextTrimmed(int droppedMessageCount) {
    turn.addAlert('Context trimmed: dropped $droppedMessageCount message(s).');
    return true;
  }

  bool _onToolCalls(List<ToolCall> calls) {
    final names = calls.map((call) => call.name).toList();
    final label = names.length == 1 ? 'tool' : 'tools';
    turn.setToolAlert('Calling $label: ${names.join(', ')}');
    return true;
  }

  bool _onToolResult(ToolResult result) {
    if (!result.isError) {
      return false;
    }
    final errorText = result.errorMessage ?? 'Unknown tool error.';
    turn.addAlert('Tool ${result.name} failed: $errorText');
    return true;
  }
}
