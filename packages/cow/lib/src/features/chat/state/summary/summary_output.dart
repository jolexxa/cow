/// Outputs produced by the summary logic block.
sealed class SummaryOutput {
  const SummaryOutput();
}

/// Summary data changed — UI should rebuild.
final class SummaryChanged extends SummaryOutput {
  const SummaryChanged();
}

/// Request to run a summary generation.
final class RunSummaryRequested extends SummaryOutput {
  const RunSummaryRequested({
    required this.text,
    required this.prompt,
    required this.requestId,
  });

  final String text;
  final String prompt;
  final int requestId;
}
