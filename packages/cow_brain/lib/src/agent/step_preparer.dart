// Encapsulates per-step context preparation state for the agent loop.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/isolate/models.dart';

/// The resolved state needed by the LLM adapter for one generation step.
final class PreparedStep {
  const PreparedStep({
    required this.slice,
    required this.requiresReset,
    required this.reusePrefixMessageCount,
  });

  final ContextSlice slice;
  final bool requiresReset;
  final int reusePrefixMessageCount;
}

/// Resolves per-step generation state, eliminating the need for the agent loop
/// to manage interacting mutable variables (requiresReset, previousSlice,
/// lastEnableReasoning) directly.
final class StepPreparer {
  StepPreparer({
    required this.contextManager,
    required this.contextSize,
    required this.maxOutputTokens,
  });

  final ContextManager contextManager;
  final int contextSize;
  final int maxOutputTokens;

  bool? _lastEnableReasoning;
  ContextSlice? _previousSlice;

  PreparedStep prepare({
    required List<Message> messages,
    required List<ToolDefinition> tools,
    required bool enableReasoning,
  }) {
    final slice = contextManager.prepare(
      messages: messages,
      tools: tools,
      contextSize: contextSize,
      maxOutputTokens: maxOutputTokens,
      previousSlice: _previousSlice,
    );

    var requiresReset = slice.requiresReset;
    var reusePrefixMessageCount = slice.reusePrefixMessageCount;

    // Force reset if reasoning toggle changed (prompt format differs).
    if (_lastEnableReasoning != null &&
        _lastEnableReasoning != enableReasoning) {
      requiresReset = true;
      reusePrefixMessageCount = 0;
    }
    _lastEnableReasoning = enableReasoning;

    _previousSlice = slice;

    return PreparedStep(
      slice: slice,
      requiresReset: requiresReset,
      reusePrefixMessageCount: reusePrefixMessageCount,
    );
  }
}
