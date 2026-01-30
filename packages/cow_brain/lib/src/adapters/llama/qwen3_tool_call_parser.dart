// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:cow_brain/src/adapters/llama/llama_tool_call_parser.dart';
import 'package:cow_brain/src/isolate/models.dart';

/// Parses Qwen-style `<think>` and `<tool_call>` blocks.
final class Qwen3ToolCallParser implements LlamaToolCallParser {
  const Qwen3ToolCallParser();

  static final RegExp _thinkRegExp = RegExp(r'<think>([\s\S]*?)</think>');
  static final RegExp _toolCallRegExp = RegExp(
    r'<tool_call>([\s\S]*?)</tool_call>',
  );

  @override
  LlamaParseResult parse(String text) {
    final reasoningParts = <String>[];
    final withoutThinking = text.replaceAllMapped(_thinkRegExp, (match) {
      final reasoning = match.group(1)?.trim();
      if (reasoning != null && reasoning.isNotEmpty) {
        reasoningParts.add(reasoning);
      }
      return '';
    });

    final toolCalls = <ToolCall>[];
    final visible = StringBuffer();
    var cursor = 0;
    var callIndex = 0;

    for (final match in _toolCallRegExp.allMatches(withoutThinking)) {
      visible.write(withoutThinking.substring(cursor, match.start));
      final rawBlock = match.group(0)!;
      final payload = match.group(1);

      final parsedCall = payload == null
          ? null
          : _tryParseToolCall(payload, callIndex);
      if (parsedCall == null) {
        visible.write(rawBlock);
      } else {
        toolCalls.add(parsedCall);
        callIndex += 1;
      }

      cursor = match.end;
    }

    visible.write(withoutThinking.substring(cursor));

    final reasoningText = reasoningParts.isEmpty
        ? null
        : reasoningParts.join('\n\n');
    return LlamaParseResult(
      visibleText: visible.toString(),
      reasoningText: reasoningText,
      toolCalls: List.unmodifiable(toolCalls),
    );
  }

  ToolCall? _tryParseToolCall(String payload, int callIndex) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        return null;
      }
      final map = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );

      final name = map['name'];
      if (name is! String || name.trim().isEmpty) {
        return null;
      }

      final idValue = map['id'];
      final id = idValue is String && idValue.trim().isNotEmpty
          ? idValue
          : 'tool-call-${callIndex + 1}';

      final argumentsValue = map['arguments'];
      final arguments = argumentsValue is Map
          ? argumentsValue.map(
              (key, value) => MapEntry(key.toString(), _normalize(value)),
            )
          : <String, Object?>{};

      return ToolCall(id: id, name: name, arguments: arguments);
    } on Object catch (_) {
      return null;
    }
  }

  Object? _normalize(Object? value) {
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
}
