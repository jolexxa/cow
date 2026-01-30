// Core contracts are evolving; we defer exhaustive API docs for now.
// We return `this` to preserve the fluent append API while mutating internally.
// ignore_for_file: avoid_returning_this, public_member_api_docs

import 'dart:collection';

import 'package:cow_brain/src/isolate/models.dart';

/// Conversation with append rules that protect basic invariants.
final class Conversation {
  Conversation._(List<Message> messages) : _messages = List.of(messages);

  /// Starts an empty conversation, optionally with a leading system message.
  factory Conversation.initial({String? systemPrompt}) {
    if (systemPrompt == null) {
      return Conversation._(const []);
    }
    _requireNonEmpty(systemPrompt, 'systemPrompt');
    return Conversation._([
      Message(role: Role.system, content: systemPrompt),
    ]);
  }

  final List<Message> _messages;
  var _systemApplied = false;
  var _turnCounter = 0;
  late final UnmodifiableListView<Message> _messagesView = UnmodifiableListView(
    _messages,
  );

  List<Message> get messages => _messagesView;
  bool get systemApplied => _systemApplied;

  String beginTurn() {
    _turnCounter += 1;
    return 'turn-$_turnCounter';
  }

  Conversation setSystemApplied({required bool value}) {
    _systemApplied = value;
    return this;
  }

  Conversation addUser(String content, {String? name}) {
    _requireNonEmpty(content, 'content');
    return _append(Message(role: Role.user, content: content, name: name));
  }

  Conversation appendAssistantText(String content, {String? reasoning}) {
    return _append(
      Message(
        role: Role.assistant,
        content: content,
        reasoningContent: reasoning,
      ),
    );
  }

  Conversation appendAssistantToolCalls(
    List<ToolCall> calls, {
    String? preToolText,
    String? reasoning,
    String? name,
  }) {
    if (calls.isEmpty) {
      throw ArgumentError.value(calls, 'calls', 'must not be empty');
    }
    final duplicateIds = _findDuplicateToolCallIds(calls);
    if (duplicateIds.isNotEmpty) {
      throw ArgumentError.value(
        calls,
        'calls',
        'contains duplicate tool call ids: ${duplicateIds.join(', ')}',
      );
    }
    return _append(
      Message(
        role: Role.assistant,
        content: preToolText ?? '',
        reasoningContent: reasoning,
        toolCalls: List.unmodifiable(calls),
        name: name,
      ),
    );
  }

  Conversation appendToolResult(ToolResult result) {
    final call = _toolCallById(result.toolCallId);
    if (call == null) {
      throw ArgumentError.value(
        result.toolCallId,
        'result.toolCallId',
        'does not exist in the conversation',
      );
    }
    if (call.name != result.name) {
      throw ArgumentError(
        'Tool result name (${result.name}) does not match the tool call '
        'name (${call.name}) for id ${result.toolCallId}.',
      );
    }
    return _append(
      Message(
        role: Role.tool,
        content: result.content,
        toolCallId: result.toolCallId,
        name: result.name,
      ),
    );
  }

  Conversation _append(Message message) {
    _messages.add(message);
    return this;
  }

  ToolCall? _toolCallById(String id) {
    for (final message in _messages) {
      for (final call in message.toolCalls) {
        if (call.id == id) {
          return call;
        }
      }
    }
    return null;
  }

  static void _requireNonEmpty(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
  }

  static Set<String> _findDuplicateToolCallIds(List<ToolCall> calls) {
    final seen = <String>{};
    final duplicates = <String>{};
    for (final call in calls) {
      if (!seen.add(call.id)) {
        duplicates.add(call.id);
      }
    }
    return duplicates;
  }
}
