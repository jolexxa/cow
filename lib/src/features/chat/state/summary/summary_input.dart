/// Inputs to the summary logic block.
sealed class SummaryInput {
  const SummaryInput();
}

/// Start tracking a new turn.
final class StartTurn extends SummaryInput {
  const StartTurn(this.turnId);

  final int turnId;
}

/// Summarize the user's message.
final class SummarizeUserMessage extends SummaryInput {
  const SummarizeUserMessage(this.text, {required this.enableReasoning});

  final String text;
  final bool enableReasoning;
}

/// A reasoning delta was received.
final class ReasoningDelta extends SummaryInput {
  const ReasoningDelta(this.text);

  final String text;
}

/// Finalize the turn (trigger final summary pass).
final class Finalize extends SummaryInput {
  const Finalize();
}

/// Freeze the summary state (turn is done).
final class Freeze extends SummaryInput {
  const Freeze();
}

/// Cancel the current turn.
final class CancelSummary extends SummaryInput {
  const CancelSummary();
}

/// Reset the summary controller.
final class ResetSummary extends SummaryInput {
  const ResetSummary();
}

/// Summary generation completed successfully.
final class SummaryComplete extends SummaryInput {
  const SummaryComplete(this.summary, {required this.requestId});

  final String summary;
  final int requestId;
}

/// Summary generation failed.
final class SummaryFailed extends SummaryInput {
  const SummaryFailed(this.error, {required this.requestId});

  final Object error;
  final int requestId;
}
