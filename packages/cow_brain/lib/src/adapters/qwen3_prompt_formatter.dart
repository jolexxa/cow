// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: lines_longer_than_80_chars, public_member_api_docs

import 'dart:convert';

import 'package:cow_brain/src/adapters/prompt_formatter.dart';
import 'package:cow_brain/src/isolate/models.dart';

/*

{%- if tools %}
    {{- '<|im_start|>system\n' }}
    {%- if messages[0].role == 'system' %}
        {{- messages[0].content + '\n\n' }}
    {%- endif %}
    {{- "# Tools\n\nYou may call one or more functions to assist with the user query.\n\nYou are provided with function signatures within <tools></tools> XML tags:\n<tools>" }}
    {%- for tool in tools %}
        {{- "\n" }}
        {{- tool | tojson }}
    {%- endfor %}
    {{- "\n</tools>\n\nFor each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:\n<tool_call>\n{\"name\": <function-name>, \"arguments\": <args-json-object>}\n</tool_call><|im_end|>\n" }}
{%- else %}
    {%- if messages[0].role == 'system' %}
        {{- '<|im_start|>system\n' + messages[0].content + '<|im_end|>\n' }}
    {%- endif %}
{%- endif %}
{%- set ns = namespace(multi_step_tool=true, last_query_index=messages|length - 1) %}
{%- for index in range(ns.last_query_index, -1, -1) %}
    {%- set message = messages[index] %}
    {%- if ns.multi_step_tool and message.role == "user" and not('<tool_response>' in message.content and '</tool_response>' in message.content) %}
        {%- set ns.multi_step_tool = false %}
        {%- set ns.last_query_index = index %}
    {%- endif %}
{%- endfor %}
{%- for message in messages %}
    {%- if (message.role == "user") or (message.role == "system" and not loop.first) %}
        {{- '<|im_start|>' + message.role + '\n' + message.content + '<|im_end|>' + '\n' }}
    {%- elif message.role == "assistant" %}
        {%- set content = message.content %}
        {%- set reasoning_content = '' %}
        {%- if message.reasoning_content is defined and message.reasoning_content is not none %}
            {%- set reasoning_content = message.reasoning_content %}
        {%- else %}
            {%- if '</think>' in message.content %}
                {%- set content = message.content.split('</think>')[-1].lstrip('\n') %}
                {%- set reasoning_content = message.content.split('</think>')[0].rstrip('\n').split('<think>')[-1].lstrip('\n') %}
            {%- endif %}
        {%- endif %}
        {%- if loop.index0 > ns.last_query_index %}
            {%- if loop.last or (not loop.last and reasoning_content) %}
                {{- '<|im_start|>' + message.role + '\n<think>\n' + reasoning_content.strip('\n') + '\n</think>\n\n' + content.lstrip('\n') }}
            {%- else %}
                {{- '<|im_start|>' + message.role + '\n' + content }}
            {%- endif %}
        {%- else %}
            {{- '<|im_start|>' + message.role + '\n' + content }}
        {%- endif %}
        {%- if message.tool_calls %}
            {%- for tool_call in message.tool_calls %}
                {%- if (loop.first and content) or (not loop.first) %}
                    {{- '\n' }}
                {%- endif %}
                {%- if tool_call.function %}
                    {%- set tool_call = tool_call.function %}
                {%- endif %}
                {{- '<tool_call>\n{"name": "' }}
                {{- tool_call.name }}
                {{- '", "arguments": ' }}
                {%- if tool_call.arguments is string %}
                    {{- tool_call.arguments }}
                {%- else %}
                    {{- tool_call.arguments | tojson }}
                {%- endif %}
                {{- '}\n</tool_call>' }}
            {%- endfor %}
        {%- endif %}
        {{- '<|im_end|>\n' }}
    {%- elif message.role == "tool" %}
        {%- if loop.first or (messages[loop.index0 - 1].role != "tool") %}
            {{- '<|im_start|>user' }}
        {%- endif %}
        {{- '\n<tool_response>\n' }}
        {{- message.content }}
        {{- '\n</tool_response>' }}
        {%- if loop.last or (messages[loop.index0 + 1].role != "tool") %}
            {{- '<|im_end|>\n' }}
        {%- endif %}
    {%- endif %}
{%- endfor %}
{%- if add_generation_prompt %}
    {{- '<|im_start|>assistant\n' }}
    {%- if enable_thinking is defined and enable_thinking is false %}
        {{- '<think>\n\n</think>\n\n' }}
    {%- endif %}
{%- endif %}

*/

/// Qwen 3 chat template (listed above in this file) with support for tools
/// and reasoning.
/// <https://huggingface.co/Qwen/Qwen3-8B-GGUF?chat_template=default>
final class Qwen3PromptFormatter implements PromptFormatter {
  const Qwen3PromptFormatter();

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
        buffer.write('<|im_start|>system\n');
        if (messages.isNotEmpty && messages.first.role == Role.system) {
          buffer
            ..write(messages.first.content)
            ..write('\n\n');
        }
        buffer.write(
          '# Tools\n\nYou may call one or more functions to assist with the '
          'user query.\n\nYou are provided with function signatures within '
          '<tools></tools> XML tags:\n<tools>',
        );
        for (final tool in toolList) {
          buffer
            ..write('\n')
            ..write(jsonEncode(_toolDeclaration(tool)));
        }
        buffer.write(
          '\n</tools>\n\nFor each function call, return a json object with '
          'function name and arguments within <tool_call></tool_call> XML tags:'
          '\n<tool_call>\n{"name": <function-name>, "arguments": '
          '<args-json-object>}\n</tool_call><|im_end|>\n',
        );
      } else if (messages.isNotEmpty && messages.first.role == Role.system) {
        buffer
          ..write('<|im_start|>system\n')
          ..write(messages.first.content)
          ..write('<|im_end|>\n');
      }
    }

    var lastQueryIndex = messages.length - 1;
    var multiStepTool = true;
    for (var i = messages.length - 1; i >= 0; i -= 1) {
      final message = messages[i];
      if (multiStepTool &&
          message.role == Role.user &&
          !(message.content.contains('<tool_response>') &&
              message.content.contains('</tool_response>'))) {
        multiStepTool = false;
        lastQueryIndex = i;
      }
    }

    for (var i = 0; i < messages.length; i += 1) {
      final message = messages[i];
      if (systemApplied && message.role == Role.system) {
        continue;
      }

      switch (message.role) {
        case Role.system:
        case Role.user:
          if (message.role == Role.system && i == 0) {
            continue;
          }
          buffer
            ..write('<|im_start|>${message.role.roleName}\n')
            ..write(message.content)
            ..write('<|im_end|>\n');
        case Role.assistant:
          var content = message.content;
          var reasoningContent = '';
          final rawReasoning = message.reasoningContent;
          if (rawReasoning != null) {
            reasoningContent = rawReasoning;
          } else if (message.content.contains('</think>')) {
            final parts = message.content.split('</think>');
            content = parts.last.replaceFirst(RegExp(r'^\n+'), '');
            final beforeThink = parts.first;
            reasoningContent = beforeThink
                .split('<think>')
                .last
                .replaceFirst(RegExp(r'^\n+'), '')
                .replaceFirst(RegExp(r'\n+$'), '');
          }

          if (i > lastQueryIndex) {
            if (i == messages.length - 1 || reasoningContent.isNotEmpty) {
              buffer
                ..write('<|im_start|>${message.role.roleName}\n')
                ..write('<think>\n')
                ..write(_stripEdgeNewlines(reasoningContent))
                ..write('\n</think>\n\n')
                ..write(_stripLeadingNewlines(content));
            } else {
              buffer
                ..write('<|im_start|>${message.role.roleName}\n')
                ..write(content);
            }
          } else {
            buffer
              ..write('<|im_start|>${message.role.roleName}\n')
              ..write(content);
          }

          for (
            var callIndex = 0;
            callIndex < message.toolCalls.length;
            callIndex += 1
          ) {
            final toolCall = message.toolCalls[callIndex];
            if ((callIndex == 0 && content.isNotEmpty) || callIndex > 0) {
              buffer.write('\n');
            }
            buffer
              ..write('<tool_call>\n{"name": "')
              ..write(toolCall.name)
              ..write('", "arguments": ')
              ..write(jsonEncode(toolCall.arguments))
              ..write('}\n</tool_call>');
          }
          buffer.write('<|im_end|>\n');
        case Role.tool:
          final previousIsTool = i > 0 && messages[i - 1].role == Role.tool;
          final nextIsTool =
              i + 1 < messages.length && messages[i + 1].role == Role.tool;
          if (!previousIsTool) {
            buffer.write('<|im_start|>user');
          }
          buffer
            ..write('\n<tool_response>\n')
            ..write(message.content)
            ..write('\n</tool_response>');
          if (!nextIsTool) {
            buffer.write('<|im_end|>\n');
          }
      }
    }

    buffer.write('<|im_start|>assistant\n');
    if (!enableReasoning) {
      buffer.write('<think>\n\n</think>\n\n');
    }
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
      'type': 'function',
      'function': <String, Object?>{
        'name': tool.name,
        'description': tool.description,
        'parameters': tool.parameters,
      },
    };
  }

  static String _stripLeadingNewlines(String value) {
    return value.replaceFirst(RegExp(r'^\n+'), '');
  }

  static String _stripEdgeNewlines(String value) {
    return value
        .replaceFirst(RegExp(r'^\n+'), '')
        .replaceFirst(
          RegExp(r'\n+$'),
          '',
        );
  }
}
