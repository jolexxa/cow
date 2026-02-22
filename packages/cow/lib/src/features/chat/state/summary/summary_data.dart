/// Mutable data container stored on the summary logic block blackboard.
final class SummaryData {
  /// The active turn ID being tracked.
  int? turnId;

  /// Buffer for accumulating reasoning text.
  final StringBuffer reasoningBuffer = StringBuffer();

  /// Word count since last summary was triggered.
  int wordsSinceSummary = 0;

  /// Whether unsummarized content exists (only meaningful in SummarizingState).
  bool dirty = false;

  /// Request ID for stale request detection.
  int requestId = 0;

  /// The current summary text to display (placeholder, actual, or failure).
  String? summaryText;

  /// Clears all turn-specific data while preserving requestId.
  void resetTurnData() {
    turnId = null;
    reasoningBuffer.clear();
    wordsSinceSummary = 0;
    dirty = false;
    summaryText = null;
  }

  /// Increments requestId and returns the new value.
  int nextRequestId() => requestId += 1;

  /// Returns the accumulated reasoning text.
  String get reasoningText => reasoningBuffer.toString();
}
