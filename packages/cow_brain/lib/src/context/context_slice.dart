// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: public_member_api_docs

import 'dart:collection';

import 'package:cow_brain/src/isolate/models.dart';

final class ContextSlice {
  ContextSlice({
    required List<Message> messages,
    required this.estimatedPromptTokens,
    required this.droppedMessageCount,
    required this.contextSize,
    required this.maxOutputTokens,
    required this.safetyMarginTokens,
    required this.budgetTokens,
    required this.remainingTokens,
    required this.reusePrefixMessageCount,
    required this.requiresReset,
  }) : messages = UnmodifiableListView(messages);

  final UnmodifiableListView<Message> messages;
  final int estimatedPromptTokens;
  final int droppedMessageCount;
  final int contextSize;
  final int maxOutputTokens;
  final int safetyMarginTokens;
  final int budgetTokens;
  final int remainingTokens;

  /// Number of leading messages that are identical to the previous slice.
  final int reusePrefixMessageCount;

  /// Whether the adapter must reset native context before applying this slice.
  final bool requiresReset;
}
