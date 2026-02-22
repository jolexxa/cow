import 'package:cow_brain/src/adapters/extractors/json_tool_call_extractor.dart';
import 'package:test/test.dart';

void main() {
  group('JsonToolCallExtractor', () {
    const extractor = JsonToolCallExtractor();

    test('extracts standard Qwen/Hermes format', () {
      const text = '{"name": "search", "arguments": {"query": "cows"}}';
      final calls = extractor.extract(text);

      expect(calls, hasLength(1));
      expect(calls.single.name, 'search');
      expect(calls.single.arguments['query'], 'cows');
      expect(calls.single.id, 'tool-call-1');
    });

    test('extracts with explicit id', () {
      const text =
          '{"id": "call-42", "name": "search", "arguments": {"q": "hi"}}';
      final calls = extractor.extract(text);

      expect(calls.single.id, 'call-42');
    });

    test('extracts parameters key variant (Llama 3.1)', () {
      const text = '{"name": "lookup", "parameters": {"id": 42}}';
      final calls = extractor.extract(text);

      expect(calls, hasLength(1));
      expect(calls.single.name, 'lookup');
      expect(calls.single.arguments['id'], 42);
    });

    test('extracts OpenAI nested format', () {
      const text =
          '{"id": "fn-1", "function": {"name": "search", "arguments": '
          '{"q": "test"}}}';
      final calls = extractor.extract(text);

      expect(calls, hasLength(1));
      expect(calls.single.name, 'search');
      expect(calls.single.id, 'fn-1');
      expect(calls.single.arguments['q'], 'test');
    });

    test('double-decodes string arguments', () {
      const text = r'{"name": "search", "arguments": "{\"query\": \"cows\"}"}';
      final calls = extractor.extract(text);

      expect(calls, hasLength(1));
      expect(calls.single.arguments['query'], 'cows');
    });

    test('extracts JSON array of tool calls', () {
      const text = '''
[
  {"name": "search", "arguments": {"q": "a"}},
  {"name": "lookup", "arguments": {"id": 1}}
]
''';
      final calls = extractor.extract(text);

      expect(calls, hasLength(2));
      expect(calls[0].name, 'search');
      expect(calls[0].id, 'tool-call-1');
      expect(calls[1].name, 'lookup');
      expect(calls[1].id, 'tool-call-2');
    });

    test('extracts multiple JSON objects separated by whitespace', () {
      const text =
          '{"name": "a", "arguments": {}} {"name": "b", "arguments": {}}';
      final calls = extractor.extract(text);

      expect(calls, hasLength(2));
      expect(calls[0].name, 'a');
      expect(calls[1].name, 'b');
    });

    test('extracts code-fenced JSON', () {
      const text = '''
```json
{"name": "search", "arguments": {"q": "test"}}
```
''';
      final calls = extractor.extract(text);

      expect(calls, hasLength(1));
      expect(calls.single.name, 'search');
    });

    test('hunts for JSON objects in mixed text', () {
      const text =
          'I will call the function now: {"name": "search", "arguments": '
          '{"q": "cow"}} and that is it.';
      final calls = extractor.extract(text);

      expect(calls, hasLength(1));
      expect(calls.single.name, 'search');
    });

    test('returns empty for plain text', () {
      final calls = extractor.extract('Hello world, nothing to see here.');
      expect(calls, isEmpty);
    });

    test('returns empty for empty string', () {
      final calls = extractor.extract('');
      expect(calls, isEmpty);
    });

    test('returns empty for malformed JSON', () {
      final calls = extractor.extract('{bad json}');
      expect(calls, isEmpty);
    });

    test('returns empty for JSON object without name key', () {
      final calls = extractor.extract('{"type": "function", "value": 42}');
      expect(calls, isEmpty);
    });

    test('coerces non-map arguments to empty map', () {
      const text = '{"name": "search", "arguments": "not-a-map"}';
      final calls = extractor.extract(text);

      expect(calls, hasLength(1));
      expect(calls.single.arguments, isEmpty);
    });

    test('normalizes nested maps and lists', () {
      const text =
          '{"name": "fn", "arguments": {"items": [1, {"k": 2}], "nested": '
          '{"x": 3}}}';
      final calls = extractor.extract(text);

      expect(calls, hasLength(1));
      expect(calls.single.arguments['items'], [
        1,
        {'k': 2},
      ]);
      expect(calls.single.arguments['nested'], {'x': 3});
    });

    test('generates sequential ids for multiple calls', () {
      const text = '''
[
  {"name": "a", "arguments": {}},
  {"name": "b", "arguments": {}},
  {"name": "c", "arguments": {}}
]
''';
      final calls = extractor.extract(text);

      expect(calls, hasLength(3));
      expect(calls[0].id, 'tool-call-1');
      expect(calls[1].id, 'tool-call-2');
      expect(calls[2].id, 'tool-call-3');
    });
  });
}
