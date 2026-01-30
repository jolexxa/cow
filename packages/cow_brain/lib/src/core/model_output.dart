// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/isolate/models.dart';

/// Thrown when generation is cancelled by the caller.
final class CancelledException implements Exception {
  const CancelledException();
}

sealed class ModelOutput {
  const ModelOutput();
}

final class OutputTextDelta extends ModelOutput {
  const OutputTextDelta(this.text);
  final String text;
}

/// Hidden/auxiliary reasoning channel (for models that expose it).
final class OutputReasoningDelta extends ModelOutput {
  const OutputReasoningDelta(this.text);
  final String text;
}

final class OutputToolCalls extends ModelOutput {
  const OutputToolCalls(this.calls);
  final List<ToolCall> calls;
}

/// Indicates how many output tokens were generated since the last update.
final class OutputTokensGenerated extends ModelOutput {
  const OutputTokensGenerated(this.count);
  final int count;
}

/// Indicates the model has finished this step and why.
final class OutputStepFinished extends ModelOutput {
  const OutputStepFinished(this.reason);
  final FinishReason reason;
}
