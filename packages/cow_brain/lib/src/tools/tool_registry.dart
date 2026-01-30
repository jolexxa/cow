// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:collection';

import 'package:cow_brain/src/isolate/models.dart';

typedef ToolHandler = FutureOr<String> Function(Map<String, Object?> arguments);

/// Registry of tools that exposes model-facing definitions and executes calls.
final class ToolRegistry {
  final Map<String, _RegisteredTool> _toolsByName = <String, _RegisteredTool>{};
  final List<ToolDefinition> _definitions = <ToolDefinition>[];
  late final UnmodifiableListView<ToolDefinition> _definitionsView =
      UnmodifiableListView(_definitions);

  List<ToolDefinition> get definitions => _definitionsView;

  void register(ToolDefinition definition, ToolHandler handler) {
    final existing = _toolsByName[definition.name];
    if (existing != null) {
      throw ArgumentError.value(
        definition.name,
        'definition.name',
        'is already registered',
      );
    }
    _toolsByName[definition.name] = _RegisteredTool(definition, handler);
    _definitions.add(definition);
  }

  Future<List<ToolResult>> executeAll(List<ToolCall> calls) {
    final futures = calls.map(_executeSingle).toList(growable: false);
    // Future.wait preserves the order of [futures], giving us stable ordering
    // while still executing in parallel.
    return Future.wait(futures);
  }

  Future<ToolResult> _executeSingle(ToolCall call) async {
    final registered = _toolsByName[call.name];
    if (registered == null) {
      return ToolResult(
        toolCallId: call.id,
        name: call.name,
        content: '',
        isError: true,
        errorMessage: 'No tool registered with name "${call.name}".',
      );
    }

    try {
      final content = await registered.handler(call.arguments);
      return ToolResult(toolCallId: call.id, name: call.name, content: content);
    } on Object catch (error) {
      final errorMessage = '${error.runtimeType}: $error';
      return ToolResult(
        toolCallId: call.id,
        name: call.name,
        content: '',
        isError: true,
        errorMessage: errorMessage,
      );
    }
  }
}

final class _RegisteredTool {
  const _RegisteredTool(this.definition, this.handler);

  final ToolDefinition definition;
  final ToolHandler handler;
}
