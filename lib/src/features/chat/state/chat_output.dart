import 'package:cow/src/features/chat/state/active_turn.dart';
import 'package:cow/src/features/chat/state/models/brain_role.dart';
import 'package:cow_brain/cow_brain.dart';

/// Outputs produced by the chat session state machine.
sealed class ChatOutput {
  const ChatOutput();
}

/// Blackboard data changed within the same state — re-derive UI state.
final class StateUpdated extends ChatOutput {
  const StateUpdated();
}

/// Request the adapter to load models.
final class LoadModelsRequested extends ChatOutput {
  const LoadModelsRequested({required this.enableReasoning});

  final bool enableReasoning;
}

/// Request the adapter to start streaming a turn.
final class StartTurnRequested extends ChatOutput {
  const StartTurnRequested({
    required this.userMessage,
    required this.enableReasoning,
  });

  final String userMessage;
  final bool enableReasoning;
}

/// Request the adapter to execute tool calls.
final class ExecuteToolCallsRequested extends ChatOutput {
  const ExecuteToolCallsRequested({
    required this.event,
    required this.turnId,
  });

  final AgentToolCalls event;
  final String turnId;
}

/// Request the adapter to handle a reasoning delta for summary.
final class ReasoningSummaryRequested extends ChatOutput {
  const ReasoningSummaryRequested({required this.turn, required this.text});

  final ActiveTurn turn;
  final String text;
}

/// Request the adapter to start summary for a user message.
final class SummarizeUserMessageRequested extends ChatOutput {
  const SummarizeUserMessageRequested({
    required this.turn,
    required this.text,
    required this.enableReasoning,
  });

  final ActiveTurn turn;
  final String text;
  final bool enableReasoning;
}

/// Request the adapter to freeze the summary for the current turn.
final class FreezeSummaryRequested extends ChatOutput {
  const FreezeSummaryRequested({required this.turn});

  final ActiveTurn turn;
}

/// Request the adapter to cancel the active summary.
final class CancelSummaryRequested extends ChatOutput {
  const CancelSummaryRequested();
}

/// Request the adapter to reset the summary controller.
final class ResetSummaryRequested extends ChatOutput {
  const ResetSummaryRequested();
}

/// Request the adapter to start summary for a turn.
final class StartSummaryTurnRequested extends ChatOutput {
  const StartSummaryTurnRequested({required this.responseId});

  final int responseId;
}

/// Request the adapter to initialize brains after models are loaded.
final class InitializeBrainsRequested extends ChatOutput {
  const InitializeBrainsRequested({
    required this.models,
    required this.enableReasoning,
  });

  final Map<BrainRole, LoadedModel> models;
  final bool enableReasoning;
}
