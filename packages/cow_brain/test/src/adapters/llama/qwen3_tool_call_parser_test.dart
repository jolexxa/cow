import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:test/test.dart';

void main() {
  group('Qwen3ToolCallParser', () {
    const parser = Qwen3ToolCallParser();

    test('extracts reasoning, visible text, and tool calls', () {
      const input = '''
Hello there.
<think>Plan quietly.</think>
<tool_call>{"id":"call-1","name":"search","arguments":{"query":"cows"}}</tool_call>
All done.
''';

      final result = parser.parse(input);

      expect(result.reasoningText, 'Plan quietly.');
      expect(result.visibleText, contains('Hello there.'));
      expect(result.visibleText, contains('All done.'));
      expect(result.visibleText, isNot(contains('<tool_call>')));
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.id, 'call-1');
      expect(result.toolCalls.single.name, 'search');
      expect(result.toolCalls.single.arguments['query'], 'cows');
    });

    test('generates stable ids when the id field is missing', () {
      const input = '<tool_call>{"name":"search","arguments":{}}</tool_call>';

      final result = parser.parse(input);

      expect(result.toolCalls.single.id, 'tool-call-1');
    });

    test('leaves malformed tool call blocks in the visible text', () {
      const input = 'Before<tool_call>{bad json}</tool_call>After';

      final result = parser.parse(input);

      expect(result.toolCalls, isEmpty);
      expect(result.visibleText, contains('<tool_call>{bad json}</tool_call>'));
    });

    test('coerces non-map arguments to an empty map', () {
      const input =
          '<tool_call>{"name":"search","arguments":"not-a-map"}</tool_call>';

      final result = parser.parse(input);

      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.arguments, isEmpty);
    });

    test('normalizes nested maps and lists in arguments', () {
      const input = '''
<tool_call>{"name":"search","arguments":{"items":[1,{"k":2},["a"]],"nested":{"x":[{"y":3}]}}}</tool_call>
''';

      final result = parser.parse(input);

      expect(result.toolCalls, hasLength(1));
      final args = result.toolCalls.single.arguments;
      expect(args['items'], [
        1,
        {'k': 2},
        ['a'],
      ]);
      expect(args['nested'], {
        'x': [
          {'y': 3},
        ],
      });
    });
  });
}
