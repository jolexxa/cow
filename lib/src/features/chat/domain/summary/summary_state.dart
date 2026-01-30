/// Encapsulates summarization bookkeeping for a single turn.
///
/// Owned by `SummaryController`, not by `ActiveTurn`. This separation ensures
/// that `ActiveTurn` remains a pure streaming accumulator with no UI concerns.
final class SummaryState {
  final StringBuffer _reasoningBuffer = StringBuffer();
  bool dirty = false;
  int wordsSinceSummary = 0;
  bool frozen = false;

  void appendReasoning(String text) {
    _reasoningBuffer.write(text);
  }

  void freeze() {
    frozen = true;
  }

  void markClean() {
    dirty = false;
    wordsSinceSummary = 0;
  }

  String get reasoningText => _reasoningBuffer.toString();
}
