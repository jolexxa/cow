// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: one_member_abstracts, public_member_api_docs

import 'package:cow_brain/src/context/context_slice.dart';
import 'package:cow_brain/src/context/token_counter.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/utils/message_list_extensions.dart';

abstract interface class ContextManager {
  ContextSlice prepare({
    required List<Message> messages,
    required List<ToolDefinition> tools,
    required int contextSize,
    required int maxOutputTokens,
    required bool systemApplied,
    ContextSlice? previousSlice,
  });
}

/// Deterministic sliding-window context manager that drops whole messages.
final class SlidingWindowContextManager implements ContextManager {
  SlidingWindowContextManager({
    required TokenCounter counter,
    this.safetyMarginTokens = 0,
  }) : _counter = counter;

  final TokenCounter _counter;
  final int safetyMarginTokens;

  @override
  ContextSlice prepare({
    required List<Message> messages,
    required List<ToolDefinition> tools,
    required int contextSize,
    required int maxOutputTokens,
    required bool systemApplied,
    ContextSlice? previousSlice,
  }) {
    final budget = contextSize - maxOutputTokens - safetyMarginTokens;
    if (budget <= 0) {
      throw ArgumentError.value(
        budget,
        'budget',
        'must be positive after reserving output and safety margin tokens',
      );
    }

    final pinnedPrefixCount = messages.pinnedPrefixCount(
      systemApplied: systemApplied,
    );
    final working = List<Message>.of(messages);

    var estimated = _counter.countPromptTokens(
      messages: working,
      tools: tools,
      systemApplied: systemApplied,
    );
    var dropped = 0;

    while (estimated > budget && working.length > pinnedPrefixCount) {
      working.removeAt(pinnedPrefixCount);
      dropped += 1;
      estimated = _counter.countPromptTokens(
        messages: working,
        tools: tools,
        systemApplied: systemApplied,
      );
    }

    if (estimated > budget) {
      throw StateError(
        'Unable to fit prompt within budget without truncating messages. '
        'Estimated=$estimated, budget=$budget.',
      );
    }

    final reusePrefixMessageCount = previousSlice == null
        ? 0
        : previousSlice.messages.sharedPrefixLength(working);
    final requiresReset =
        previousSlice != null &&
        reusePrefixMessageCount < previousSlice.messages.length;

    return ContextSlice(
      messages: working,
      estimatedPromptTokens: estimated,
      droppedMessageCount: dropped,
      contextSize: contextSize,
      maxOutputTokens: maxOutputTokens,
      safetyMarginTokens: safetyMarginTokens,
      budgetTokens: budget,
      remainingTokens: budget - estimated,
      reusePrefixMessageCount: reusePrefixMessageCount,
      requiresReset: requiresReset,
    );
  }
}
