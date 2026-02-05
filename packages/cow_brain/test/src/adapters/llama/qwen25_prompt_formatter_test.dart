import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

void main() {
  group('Qwen25PromptFormatter', () {
    const formatter = Qwen25PromptFormatter();

    test('uses the first system message when tools are present', () {
      final output = formatter.format(
        messages: const <Message>[
          Message(role: Role.system, content: 'System header'),
          Message(role: Role.user, content: 'Hi'),
        ],
        tools: const <ToolDefinition>[
          ToolDefinition(
            name: 'search',
            description: 'Search',
            parameters: <String, Object?>{},
          ),
        ],
        systemApplied: false,
        enableReasoning: true,
      );

      expect(output, contains('System header'));
    });

    test('uses the first system message without tools', () {
      final output = formatter.format(
        messages: const <Message>[
          Message(role: Role.system, content: 'System only'),
          Message(role: Role.user, content: 'Hi'),
        ],
        tools: const <ToolDefinition>[],
        systemApplied: false,
        enableReasoning: true,
      );

      expect(output, contains('System only'));
      expect(output, contains('<|im_start|>system'));
    });

    test('emits tool instructions with plain tool schemas', () {
      final output = formatter.format(
        messages: const <Message>[
          Message(role: Role.user, content: 'Hi'),
        ],
        tools: const <ToolDefinition>[
          ToolDefinition(
            name: 'search',
            description: 'Search',
            parameters: <String, Object?>{},
          ),
        ],
        systemApplied: false,
        enableReasoning: true,
      );

      expect(output, contains('# Tools'));
      expect(output, contains('"name":"search"'));
      expect(output, isNot(contains('"type":"function"')));
      expect(output, contains('<tool_call>'));
      expect(output, contains('"name": <function-name>'));
      expect(output, isNot(contains('"id": <tool-call-id>')));
    });

    test('uses the default system prompt when none is provided', () {
      final output = formatter.format(
        messages: const <Message>[
          Message(role: Role.user, content: 'Hello'),
        ],
        tools: const <ToolDefinition>[],
        systemApplied: false,
        enableReasoning: true,
      );

      expect(
        output,
        contains('You are Qwen, created by Alibaba Cloud.'),
      );
    });

    test('includes non-leading system messages in the prompt', () {
      final output = formatter.format(
        messages: const <Message>[
          Message(role: Role.user, content: 'Hi'),
          Message(role: Role.system, content: 'System after user'),
        ],
        tools: const <ToolDefinition>[],
        systemApplied: false,
        enableReasoning: true,
      );

      expect(output, contains('System after user'));
      expect(output, contains('<|im_start|>system'));
    });

    test('formats assistant messages without tool calls', () {
      final output = formatter.format(
        messages: const <Message>[
          Message(role: Role.assistant, content: 'Plain response'),
        ],
        tools: const <ToolDefinition>[],
        systemApplied: false,
        enableReasoning: true,
      );

      expect(output, contains('<|im_start|>assistant'));
      expect(output, contains('Plain response'));
      expect(output, contains('<|im_end|>'));
    });

    test('omits empty assistant content when tool calls are present', () {
      final output = formatter.format(
        messages: const <Message>[
          Message(
            role: Role.assistant,
            content: '',
            toolCalls: <ToolCall>[
              ToolCall(
                id: 'ignored',
                name: 'lookup',
                arguments: <String, Object?>{'id': 2},
              ),
            ],
          ),
        ],
        tools: const <ToolDefinition>[],
        systemApplied: false,
        enableReasoning: true,
      );

      final assistantIndex = output.indexOf('<|im_start|>assistant');
      final toolIndex = output.indexOf('<tool_call>');
      expect(assistantIndex, lessThan(toolIndex));
    });

    test('formats assistant tool calls without ids', () {
      final output = formatter.format(
        messages: const <Message>[
          Message(
            role: Role.assistant,
            content: 'Checking.',
            toolCalls: <ToolCall>[
              ToolCall(
                id: 'ignored',
                name: 'lookup',
                arguments: <String, Object?>{'id': 1},
              ),
            ],
          ),
        ],
        tools: const <ToolDefinition>[],
        systemApplied: false,
        enableReasoning: true,
      );

      expect(output, contains('<tool_call>'));
      expect(output, contains('"name": "lookup"'));
      expect(output, contains('"arguments": {"id":1}'));
      expect(output, isNot(contains('"id":"ignored"')));
      expect(output, isNot(contains('"id": "ignored"')));
    });

    test('wraps a single tool response in its own user block', () {
      final output = formatter.format(
        messages: const <Message>[
          Message(role: Role.tool, content: 'Only tool'),
        ],
        tools: const <ToolDefinition>[],
        systemApplied: false,
        enableReasoning: true,
      );

      expect(output, contains('<|im_start|>user'));
      expect(output, contains('<|im_end|>'));
      expect(output, contains('<tool_response>'));
    });

    test('groups tool responses in a single user block', () {
      final output = formatter.format(
        messages: const <Message>[
          Message(role: Role.tool, content: 'A'),
          Message(role: Role.tool, content: 'B'),
        ],
        tools: const <ToolDefinition>[],
        systemApplied: false,
        enableReasoning: true,
      );

      final startCount = _count(output, '<|im_start|>user');
      final responseCount = _count(output, '<tool_response>');
      final endCount = _count(output, '<|im_end|>');

      expect(startCount, 1);
      expect(responseCount, 2);
      expect(endCount, greaterThanOrEqualTo(1));
    });

    test('skips system messages when systemApplied is true', () {
      final output = formatter.format(
        messages: const <Message>[
          Message(role: Role.system, content: 'Should be skipped'),
          Message(role: Role.user, content: 'Hello'),
        ],
        tools: const <ToolDefinition>[],
        systemApplied: true,
        enableReasoning: true,
      );

      expect(output, isNot(contains('Should be skipped')));
      expect(output, contains('Hello'));
    });

    test('exposes stop sequences and BOS setting', () {
      expect(
        formatter.stopSequences,
        const <String>['<|im_end|>', '<|im_start|>'],
      );
      expect(formatter.addBos, isTrue);
    });

    test('formats assistant tool calls with content and closes the block', () {
      final output = formatter.format(
        messages: const <Message>[
          Message(
            role: Role.assistant,
            content: 'Working',
            toolCalls: <ToolCall>[
              ToolCall(
                id: 'ignored',
                name: 'search',
                arguments: <String, Object?>{'q': 'cows'},
              ),
              ToolCall(
                id: 'ignored-2',
                name: 'lookup',
                arguments: <String, Object?>{'id': 2},
              ),
            ],
          ),
        ],
        tools: const <ToolDefinition>[],
        systemApplied: false,
        enableReasoning: true,
      );

      expect(output, contains('Working'));
      expect(_count(output, '<tool_call>'), 2);
      expect(output, contains('<|im_end|>'));
    });

    test('closes tool response blocks before the next user message', () {
      final output = formatter.format(
        messages: const <Message>[
          Message(role: Role.user, content: 'Hi'),
          Message(role: Role.tool, content: 'Tool response'),
          Message(role: Role.user, content: 'Thanks'),
        ],
        tools: const <ToolDefinition>[],
        systemApplied: false,
        enableReasoning: true,
      );

      final toolResponseIndex = output.indexOf('<tool_response>');
      final endIndex = output.indexOf('<|im_end|>', toolResponseIndex);
      final nextUserIndex = output.indexOf('<|im_start|>user', endIndex + 1);
      expect(toolResponseIndex, greaterThanOrEqualTo(0));
      expect(endIndex, greaterThan(toolResponseIndex));
      expect(nextUserIndex, greaterThan(endIndex));
    });
  });
}

int _count(String haystack, String needle) {
  var count = 0;
  var index = 0;
  while (true) {
    index = haystack.indexOf(needle, index);
    if (index == -1) return count;
    count += 1;
    index += needle.length;
  }
}
