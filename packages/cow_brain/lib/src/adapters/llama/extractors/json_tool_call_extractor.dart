// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:cow_brain/src/adapters/llama/tool_call_extractor.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/utils/json_brace_utils.dart' as json_utils;

/// Extracts tool calls from JSON-formatted text.
///
/// Handles multiple formats:
/// 1. `{"name": "fn", "arguments": {...}}`  (Qwen/Hermes standard)
/// 2. `{"name": "fn", "parameters": {...}}`  (Llama 3.1 variant)
/// 3. `{"function": {"name": "fn", "arguments": {...}}}`  (OpenAI nesting)
/// 4. `"arguments"` as JSON string → double-decode
/// 5. JSON arrays `[{...}, {...}]`
/// 6. Multiple JSON objects separated by whitespace
/// 7. Code-fenced JSON (` ```json ... ``` `)
/// 8. JSON hunting — scan for `{...}` objects with `"name"` key
final class JsonToolCallExtractor implements ToolCallExtractor {
  const JsonToolCallExtractor();

  @override
  List<ToolCall> extract(String text) {
    final cleaned = _stripCodeFences(text).trim();
    if (cleaned.isEmpty) return const [];

    // Try direct parse first (most common).
    final directResult = _tryDirectParse(cleaned);
    if (directResult.isNotEmpty) return directResult;

    // Fall back to hunting for JSON objects.
    return _huntJsonObjects(cleaned);
  }

  static String _stripCodeFences(String text) {
    return text.replaceAllMapped(
      RegExp(r'```(?:json)?\s*([\s\S]*?)```'),
      (m) => m.group(1)!,
    );
  }

  static List<ToolCall> _tryDirectParse(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return _extractFromList(decoded);
      }
      if (decoded is Map) {
        final call = _tryParseObject(
          decoded.map((k, v) => MapEntry(k.toString(), v)),
          0,
        );
        if (call != null) return [call];
      }
    } on Object catch (_) {
      // Not valid JSON as a whole — try multi-object parsing.
    }

    // Try multiple JSON objects separated by whitespace.
    return _parseMultipleObjects(text);
  }

  static List<ToolCall> _extractFromList(List<Object?> list) {
    final calls = <ToolCall>[];
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is! Map) continue;
      final map = item.map((k, v) => MapEntry(k.toString(), v));
      final call = _tryParseObject(map, calls.length);
      if (call != null) calls.add(call);
    }
    return calls;
  }

  static List<ToolCall> _parseMultipleObjects(String text) {
    final calls = <ToolCall>[];
    var pos = 0;
    while (pos < text.length) {
      // Skip whitespace.
      while (pos < text.length && _isWhitespace(text.codeUnitAt(pos))) {
        pos++;
      }
      if (pos >= text.length) break;
      if (text.codeUnitAt(pos) != 0x7B /* { */ ) break;

      final end = json_utils.findMatchingBrace(text, pos);
      if (end == null) break;

      try {
        final decoded = jsonDecode(text.substring(pos, end + 1));
        if (decoded is Map) {
          final map = decoded.map((k, v) => MapEntry(k.toString(), v));
          final call = _tryParseObject(map, calls.length);
          if (call != null) calls.add(call);
        }
      } on Object catch (_) {
        // Skip invalid JSON.
      }
      pos = end + 1;
    }
    return calls;
  }

  static List<ToolCall> _huntJsonObjects(String text) {
    final calls = <ToolCall>[];
    var pos = 0;
    while (pos < text.length) {
      final braceIndex = text.indexOf('{', pos);
      if (braceIndex == -1) break;

      final end = json_utils.findMatchingBrace(text, braceIndex);
      if (end == null) {
        pos = braceIndex + 1;
        continue;
      }

      try {
        final decoded = jsonDecode(text.substring(braceIndex, end + 1));
        if (decoded is Map) {
          final map = decoded.map((k, v) => MapEntry(k.toString(), v));
          final call = _tryParseObject(map, calls.length);
          if (call != null) {
            calls.add(call);
            pos = end + 1;
            continue;
          }
        }
      } on Object catch (_) {
        // Not valid JSON.
      }
      pos = braceIndex + 1;
    }
    return calls;
  }

  static ToolCall? _tryParseObject(Map<String, Object?> map, int callIndex) {
    // OpenAI nesting: {"function": {"name": ..., "arguments": ...}}
    if (map.containsKey('function') && map['function'] is Map) {
      final inner = (map['function']! as Map).map(
        (k, v) => MapEntry(k.toString(), v),
      );
      final id = map['id'] is String ? map['id']! as String : null;
      return _extractToolCall(inner, callIndex, idOverride: id);
    }

    return _extractToolCall(map, callIndex);
  }

  static ToolCall? _extractToolCall(
    Map<String, Object?> map,
    int callIndex, {
    String? idOverride,
  }) {
    final name = map['name'];
    if (name is! String || name.trim().isEmpty) return null;

    final idValue = idOverride ?? map['id'];
    final id = idValue is String && idValue.trim().isNotEmpty
        ? idValue
        : 'tool-call-${callIndex + 1}';

    // Support both "arguments" and "parameters" keys.
    var argumentsValue = map['arguments'] ?? map['parameters'];

    // Double-decode if arguments is a JSON string.
    if (argumentsValue is String) {
      try {
        argumentsValue = jsonDecode(argumentsValue);
      } on Object catch (_) {
        // Not valid JSON string — treat as empty.
      }
    }

    final arguments = argumentsValue is Map
        ? argumentsValue.map(
            (key, value) => MapEntry(key.toString(), _normalize(value)),
          )
        : <String, Object?>{};

    return ToolCall(id: id, name: name, arguments: arguments);
  }

  static Object? _normalize(Object? value) {
    if (value is Map) {
      return value.map(
        (key, entryValue) => MapEntry(key.toString(), _normalize(entryValue)),
      );
    }
    if (value is List) {
      return value.map(_normalize).toList(growable: false);
    }
    return value;
  }

  static bool _isWhitespace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
}
