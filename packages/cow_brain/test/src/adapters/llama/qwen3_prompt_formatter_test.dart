import 'package:cow_brain/src/adapters/qwen3_prompt_formatter.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

void main() {
  group('QwenPromptFormatter', () {
    const formatter = Qwen3PromptFormatter();
    const tool = ToolDefinition(
      name: 'search',
      description: 'Search the web',
      parameters: {'type': 'object'},
    );

    test('includes tool declarations, tool calls, and tool responses', () {
      final prompt = formatter.format(
        messages: const [
          Message(role: Role.system, content: 'You are helpful.'),
          Message(role: Role.user, content: 'Find facts about cows.'),
          Message(
            role: Role.assistant,
            content: 'Let me check.',
            toolCalls: [
              ToolCall(
                id: 'call-1',
                name: 'search',
                arguments: {'query': 'cows'},
              ),
            ],
          ),
          Message(
            role: Role.tool,
            content: 'Cows are large mammals.',
            toolCallId: 'call-1',
            name: 'search',
          ),
        ],
        tools: const [tool],
        systemApplied: false,
        enableReasoning: true,
      );

      expect(prompt, contains('<tools>'));
      expect(prompt, contains('"name":"search"'));
      expect(prompt, contains('<tool_call>'));
      expect(prompt, contains('"name": "search"'));
      expect(prompt, contains('<tool_response>'));
      expect(prompt.trimRight(), endsWith('<|im_start|>assistant'));
    });

    test('skips system messages when systemApplied is true', () {
      final prompt = formatter.format(
        messages: const [
          Message(role: Role.system, content: 'System prompt.'),
          Message(role: Role.user, content: 'Hello.'),
        ],
        tools: const [],
        systemApplied: true,
        enableReasoning: true,
      );

      expect(prompt, isNot(contains('System prompt.')));
      expect(prompt, contains('Hello.'));
    });

    test('injects empty think block when reasoning is disabled', () {
      final prompt = formatter.format(
        messages: const [
          Message(role: Role.user, content: 'Hello.'),
        ],
        tools: const [],
        systemApplied: false,
        enableReasoning: false,
      );

      expect(
        prompt,
        contains('<|im_start|>assistant\n<think>\n\n</think>\n\n'),
      );
    });

    test('emits reasoning blocks for assistant messages when enabled', () {
      final prompt = formatter.format(
        messages: const [
          Message(role: Role.user, content: 'Hello.'),
          Message(
            role: Role.assistant,
            content: 'Answer',
            reasoningContent: 'Thinking',
          ),
        ],
        tools: const [],
        systemApplied: false,
        enableReasoning: true,
      );

      expect(prompt, contains('<think>'));
      expect(prompt, contains('Thinking'));
      expect(prompt, contains('</think>'));
    });

    test('tool response headers are omitted', () {
      final prompt = formatter.format(
        messages: const [
          Message(role: Role.tool, content: 'Result'),
        ],
        tools: const [],
        systemApplied: false,
        enableReasoning: true,
      );

      expect(prompt, isNot(contains('Tool:')));
      expect(prompt, contains('<tool_response>'));
    });

    test('matches the reference template prompt exactly', () {
      final prompt = formatter.format(
        messages: const [
          Message(role: Role.system, content: 'You are helpful.'),
          Message(role: Role.user, content: 'Find facts.'),
          Message(
            role: Role.assistant,
            content: 'Let me check.',
            reasoningContent: 'Plan',
            toolCalls: [
              ToolCall(
                id: 'call-1',
                name: 'search',
                arguments: {'query': 'cows'},
              ),
            ],
          ),
          Message(role: Role.tool, content: 'Result 1'),
          Message(role: Role.tool, content: 'Result 2'),
          Message(role: Role.assistant, content: 'Done.'),
        ],
        tools: const [tool],
        systemApplied: false,
        enableReasoning: true,
      );

      const expected =
          '<|im_start|>system\n'
          'You are helpful.\n'
          '\n'
          '# Tools\n'
          '\n'
          'You may call one or more functions to assist with the user query.\n'
          '\n'
          'You are provided with function signatures within <tools></tools> XML tags:\n'
          '<tools>\n'
          '{"type":"function","function":{"name":"search","description":"Search'
          ' the web","parameters":{"type":"object"}}}\n'
          '</tools>\n'
          '\n'
          'For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:\n'
          '<tool_call>\n'
          '{"name": <function-name>, "arguments": <args-json-object>}\n'
          '</tool_call><|im_end|>\n'
          '<|im_start|>user\n'
          'Find facts.<|im_end|>\n'
          '<|im_start|>assistant\n'
          '<think>\n'
          'Plan\n'
          '</think>\n'
          '\n'
          'Let me check.\n'
          '<tool_call>\n'
          '{"name": "search", "arguments": {"query":"cows"}}\n'
          '</tool_call><|im_end|>\n'
          '<|im_start|>user\n'
          '<tool_response>\n'
          'Result 1\n'
          '</tool_response>\n'
          '<tool_response>\n'
          'Result 2\n'
          '</tool_response><|im_end|>\n'
          '<|im_start|>assistant\n'
          '<think>\n'
          '\n'
          '</think>\n'
          '\n'
          'Done.<|im_end|>\n'
          '<|im_start|>assistant\n';

      expect(prompt, expected);
    });

    test('parses embedded think blocks when reasoning content is inline', () {
      final prompt = formatter.format(
        messages: const [
          Message(role: Role.user, content: 'Hi'),
          Message(
            role: Role.assistant,
            content: '<think>\nHidden\n</think>\nVisible',
          ),
        ],
        tools: const [],
        systemApplied: false,
        enableReasoning: true,
      );

      expect(prompt, contains('<think>\nHidden\n</think>\n\nVisible'));
    });

    test('keeps assistant content before the last user unwrapped', () {
      final prompt = formatter.format(
        messages: const [
          Message(role: Role.assistant, content: 'Earlier response.'),
          Message(role: Role.user, content: 'Latest question.'),
        ],
        tools: const [],
        systemApplied: false,
        enableReasoning: true,
      );

      expect(
        prompt,
        contains('<|im_start|>assistant\nEarlier response.<|im_end|>'),
      );
      expect(prompt, isNot(contains('<think>\nEarlier response.')));
    });

    test('serializes tool call arguments as json', () {
      final prompt = formatter.format(
        messages: const [
          Message(role: Role.user, content: 'Search'),
          Message(
            role: Role.assistant,
            content: 'Ok.',
            toolCalls: [
              ToolCall(
                id: 'call-1',
                name: 'search',
                arguments: {
                  'query': 'cows',
                  'filters': ['a', 'b'],
                },
              ),
            ],
          ),
        ],
        tools: const [tool],
        systemApplied: false,
        enableReasoning: true,
      );

      expect(
        prompt,
        contains(
          '{"name": "search", "arguments": '
          '{"query":"cows","filters":["a","b"]}}',
        ),
      );
    });

    test('ignores tool-response user content when locating the last query', () {
      final prompt = formatter.format(
        messages: const [
          Message(
            role: Role.user,
            content: '<tool_response>\nResult\n</tool_response>',
          ),
          Message(role: Role.assistant, content: 'Follow up.'),
        ],
        tools: const [],
        systemApplied: false,
        enableReasoning: true,
      );

      expect(prompt, contains('<|im_start|>assistant\nFollow up.<|im_end|>'));
      expect(prompt, isNot(contains('<think>\nFollow up.')));
    });

    test('lastUserMessageIndex handles missing user messages', () {
      final prompt = formatter.format(
        messages: const [
          Message(role: Role.system, content: 'System only.'),
        ],
        tools: const [],
        systemApplied: false,
        enableReasoning: true,
      );

      expect(prompt, contains('System only.'));
    });
  });
}
