// Utilities are internal refactors; we keep docs light for now.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/isolate/models.dart';

extension MessageDeepEquals on Message {
  bool deepEquals(Message other) {
    return role == other.role &&
        content == other.content &&
        reasoningContent == other.reasoningContent &&
        toolCallId == other.toolCallId &&
        name == other.name &&
        toolCalls.deepEquals(other.toolCalls);
  }
}

extension ToolCallListDeepEquals on List<ToolCall> {
  bool deepEquals(List<ToolCall> other) {
    if (length != other.length) {
      return false;
    }
    for (var index = 0; index < length; index += 1) {
      final left = this[index];
      final right = other[index];
      if (left.id != right.id || left.name != right.name) {
        return false;
      }
      if (!left.arguments.deepEquals(right.arguments)) {
        return false;
      }
    }
    return true;
  }
}

extension ToolArgumentMapDeepEquals on Map<String, Object?> {
  bool deepEquals(Map<String, Object?> other) {
    if (length != other.length) {
      return false;
    }
    for (final entry in entries) {
      if (!other.containsKey(entry.key)) {
        return false;
      }
      if (!entry.value.deepEquals(other[entry.key])) {
        return false;
      }
    }
    return true;
  }
}

extension ObjectDeepEquals on Object? {
  bool deepEquals(Object? other) {
    final self = this;
    if (self is Map<String, Object?> && other is Map<String, Object?>) {
      return self.deepEquals(other);
    }
    if (self is List<Object?> && other is List<Object?>) {
      return self.deepEquals(other);
    }
    return self == other;
  }
}

extension ObjectListDeepEquals on List<Object?> {
  bool deepEquals(List<Object?> other) {
    if (length != other.length) {
      return false;
    }
    for (var index = 0; index < length; index += 1) {
      if (!this[index].deepEquals(other[index])) {
        return false;
      }
    }
    return true;
  }
}
