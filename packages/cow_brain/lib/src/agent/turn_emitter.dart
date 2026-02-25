// Factory for AgentEvent construction — captures per-turn context.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/isolate/models.dart';

final class TurnEmitter {
  TurnEmitter({required this.sequenceId, required this.turnId});

  final int sequenceId;
  final String turnId;
  int step = 0;

  AgentStepStarted stepStarted() => AgentStepStarted(
    sequenceId: sequenceId,
    turnId: turnId,
    step: step,
  );

  AgentTelemetryUpdate telemetry(
    ContextSlice slice, {
    int? remainingOverride,
  }) => AgentTelemetryUpdate(
    sequenceId: sequenceId,
    turnId: turnId,
    step: step,
    promptTokens: slice.estimatedPromptTokens,
    budgetTokens: slice.budgetTokens,
    remainingTokens: remainingOverride ?? slice.remainingTokens,
    contextSize: slice.contextSize,
    maxOutputTokens: slice.maxOutputTokens,
    safetyMarginTokens: slice.safetyMarginTokens,
  );

  AgentContextTrimmed contextTrimmed(int droppedMessageCount) =>
      AgentContextTrimmed(
        sequenceId: sequenceId,
        turnId: turnId,
        step: step,
        droppedMessageCount: droppedMessageCount,
      );

  AgentTextDelta textDelta(String text) => AgentTextDelta(
    sequenceId: sequenceId,
    turnId: turnId,
    step: step,
    text: text,
  );

  AgentReasoningDelta reasoningDelta(String text) => AgentReasoningDelta(
    sequenceId: sequenceId,
    turnId: turnId,
    step: step,
    text: text,
  );

  AgentToolCalls toolCalls({
    required List<ToolCall> calls,
    required FinishReason finishReason,
    String? preToolText,
    String? preToolReasoning,
  }) => AgentToolCalls(
    sequenceId: sequenceId,
    turnId: turnId,
    step: step,
    calls: calls,
    finishReason: finishReason,
    preToolText: preToolText,
    preToolReasoning: preToolReasoning,
  );

  AgentToolResult toolResult(ToolResult result) => AgentToolResult(
    sequenceId: sequenceId,
    turnId: turnId,
    step: step,
    result: result,
  );

  AgentStepFinished stepFinished({
    required String text,
    required FinishReason finishReason,
    String? reasoning,
  }) => AgentStepFinished(
    sequenceId: sequenceId,
    turnId: turnId,
    step: step,
    text: text,
    finishReason: finishReason,
    reasoning: reasoning,
  );

  AgentTurnFinished turnFinished(FinishReason reason) => AgentTurnFinished(
    sequenceId: sequenceId,
    turnId: turnId,
    step: step,
    finishReason: reason,
  );

  AgentError error(String message) => AgentError(
    sequenceId: sequenceId,
    turnId: turnId,
    step: step,
    error: message,
  );
}
