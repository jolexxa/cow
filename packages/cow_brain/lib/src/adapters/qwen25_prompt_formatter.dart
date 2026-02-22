// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: lines_longer_than_80_chars, public_member_api_docs

import 'dart:convert';

import 'package:cow_brain/src/adapters/prompt_formatter.dart';
import 'package:cow_brain/src/isolate/models.dart';

// Reference template (Hugging Face): Qwen/Qwen2.5-7B-Instruct-GGUF, chat_template=default.

/// Qwen 2.5 prompt template with support for tools.
/// Based on the official template provided by Alibaba Cloud (shown above in this
/// file).
/// <https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF?chat_template=default>
final class Qwen25PromptFormatter implements PromptFormatter {
  const Qwen25PromptFormatter();

  @override
  String format({
    required List<Message> messages,
    required List<ToolDefinition> tools,
    required bool systemApplied,
    required bool enableReasoning,
  }) {
    final buffer = StringBuffer();
    final toolList = tools;

    if (!systemApplied) {
      if (toolList.isNotEmpty) {
        buffer.writeln('<|im_start|>system');
        final systemPrompt = _systemPrompt(messages);
        if (systemPrompt != null) {
          buffer.writeln(systemPrompt.trimRight());
        } else {
          buffer.writeln(
            'You are Qwen, created by Alibaba Cloud. '
            'You are a helpful assistant.',
          );
        }

        buffer
          ..writeln()
          ..writeln('# Tools')
          ..writeln()
          ..writeln(
            'You may call one or more functions to assist with the user query.',
          )
          ..writeln()
          ..writeln(
            'You are provided with function signatures within <tools></tools> '
            'XML tags:',
          )
          ..writeln('<tools>');

        for (final tool in toolList) {
          buffer
            ..writeln()
            ..write(jsonEncode(_toolDeclaration(tool)));
        }

        buffer
          ..writeln()
          ..writeln('</tools>')
          ..writeln()
          ..writeln(
            'For each function call, return a json object with function name '
            'and arguments within <tool_call></tool_call> XML tags:',
          )
          ..writeln('<tool_call>')
          ..writeln(
            '{"name": <function-name>, "arguments": <args-json-object>}',
          )
          ..writeln('</tool_call><|im_end|>');
      } else {
        final systemPrompt = _systemPrompt(messages);
        if (systemPrompt != null) {
          buffer
            ..writeln('<|im_start|>system')
            ..writeln(systemPrompt.trimRight())
            ..writeln('<|im_end|>');
        } else {
          buffer
            ..writeln('<|im_start|>system')
            ..writeln(
              'You are Qwen, created by Alibaba Cloud. '
              'You are a helpful assistant.',
            )
            ..writeln('<|im_end|>');
        }
      }
    }

    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (systemApplied && message.role == Role.system) {
        continue;
      }

      if (message.role == Role.user ||
          (message.role == Role.system && i != 0) ||
          (message.role == Role.assistant && message.toolCalls.isEmpty)) {
        buffer
          ..writeln('<|im_start|>${message.role.roleName}')
          ..writeln(message.content.trimRight())
          ..writeln('<|im_end|>');
        continue;
      }

      if (message.role == Role.assistant) {
        buffer.writeln('<|im_start|>${message.role.roleName}');
        final content = message.content.trimRight();
        if (content.isNotEmpty) {
          buffer.writeln(content);
        }
        for (final toolCall in message.toolCalls) {
          buffer
            ..writeln('<tool_call>')
            ..write('{"name": "')
            ..write(toolCall.name)
            ..write('", "arguments": ')
            ..write(jsonEncode(toolCall.arguments))
            ..writeln('}')
            ..writeln('</tool_call>');
        }
        buffer.writeln('<|im_end|>');
        continue;
      }

      if (message.role == Role.tool) {
        final previousIsTool = i > 0 && messages[i - 1].role == Role.tool;
        final nextIsTool =
            i + 1 < messages.length && messages[i + 1].role == Role.tool;
        if (!previousIsTool) {
          buffer.writeln('<|im_start|>user');
        }
        buffer
          ..writeln('<tool_response>')
          ..writeln(message.content.trimRight())
          ..writeln('</tool_response>');
        if (!nextIsTool) {
          buffer.writeln('<|im_end|>');
        }
      }
    }

    buffer.writeln('<|im_start|>assistant');
    return buffer.toString();
  }

  @override
  List<String> get stopSequences => const <String>[
    '<|im_end|>',
    '<|im_start|>',
  ];

  @override
  bool get addBos => true;

  static Map<String, Object?> _toolDeclaration(ToolDefinition tool) {
    return <String, Object?>{
      'name': tool.name,
      'description': tool.description,
      'parameters': tool.parameters,
    };
  }

  static String? _systemPrompt(List<Message> messages) {
    for (final message in messages) {
      if (message.role == Role.system) {
        return message.content;
      }
    }
    return null;
  }
}
