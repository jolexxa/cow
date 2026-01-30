import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:test/test.dart';

void main() {
  group('StreamTokenizer', () {
    late StreamTokenizer tokenizer;

    setUp(() {
      tokenizer = StreamTokenizer();
    });

    test('emits text tokens for plain text', () async {
      final chunks = Stream<String>.fromIterable(const ['Hello world']);
      final tokens = await tokenizer.tokenize(chunks).toList();

      expect(tokens, hasLength(1));
      expect(tokens[0].type, StreamTokenType.text);
      expect(tokens[0].text, 'Hello world');
    });

    test('emits think start/end tokens', () async {
      final chunks = Stream<String>.fromIterable(
        const ['<think>reasoning</think>'],
      );
      final tokens = await tokenizer.tokenize(chunks).toList();

      expect(tokens, hasLength(3));
      expect(tokens[0].type, StreamTokenType.thinkStart);
      expect(tokens[1].type, StreamTokenType.text);
      expect(tokens[1].text, 'reasoning');
      expect(tokens[2].type, StreamTokenType.thinkEnd);
    });

    test('emits tool start/end tokens', () async {
      final chunks = Stream<String>.fromIterable(
        const ['<tool_call>{"name":"test"}</tool_call>'],
      );
      final tokens = await tokenizer.tokenize(chunks).toList();

      expect(tokens, hasLength(3));
      expect(tokens[0].type, StreamTokenType.toolStart);
      expect(tokens[1].type, StreamTokenType.text);
      expect(tokens[1].text, '{"name":"test"}');
      expect(tokens[2].type, StreamTokenType.toolEnd);
    });

    test('handles tags split across chunks', () async {
      final chunks = Stream<String>.fromIterable(const [
        '<thi',
        'nk>inner</thi',
        'nk>after',
      ]);
      final tokens = await tokenizer.tokenize(chunks).toList();

      expect(tokens, hasLength(4));
      expect(tokens[0].type, StreamTokenType.thinkStart);
      expect(tokens[1].type, StreamTokenType.text);
      expect(tokens[1].text, 'inner');
      expect(tokens[2].type, StreamTokenType.thinkEnd);
      expect(tokens[3].type, StreamTokenType.text);
      expect(tokens[3].text, 'after');
    });

    test('handles text before and after tags', () async {
      final chunks = Stream<String>.fromIterable(
        const ['before<think>inner</think>after'],
      );
      final tokens = await tokenizer.tokenize(chunks).toList();

      expect(tokens, hasLength(5));
      expect(tokens[0].type, StreamTokenType.text);
      expect(tokens[0].text, 'before');
      expect(tokens[1].type, StreamTokenType.thinkStart);
      expect(tokens[2].type, StreamTokenType.text);
      expect(tokens[2].text, 'inner');
      expect(tokens[3].type, StreamTokenType.thinkEnd);
      expect(tokens[4].type, StreamTokenType.text);
      expect(tokens[4].text, 'after');
    });

    test('handles multiple sequential tags', () async {
      final chunks = Stream<String>.fromIterable(
        const ['<think>a</think><tool_call>b</tool_call>'],
      );
      final tokens = await tokenizer.tokenize(chunks).toList();

      expect(tokens, hasLength(6));
      expect(tokens[0].type, StreamTokenType.thinkStart);
      expect(tokens[1].type, StreamTokenType.text);
      expect(tokens[1].text, 'a');
      expect(tokens[2].type, StreamTokenType.thinkEnd);
      expect(tokens[3].type, StreamTokenType.toolStart);
      expect(tokens[4].type, StreamTokenType.text);
      expect(tokens[4].text, 'b');
      expect(tokens[5].type, StreamTokenType.toolEnd);
    });

    test('handles empty stream', () async {
      const chunks = Stream<String>.empty();
      final tokens = await tokenizer.tokenize(chunks).toList();

      expect(tokens, isEmpty);
    });

    test('handles single character chunks', () async {
      const text = '<think>hi</think>';
      final chunks = Stream<String>.fromIterable(text.split(''));
      final tokens = await tokenizer.tokenize(chunks).toList();

      final types = tokens.map((t) => t.type).toList();
      expect(types, contains(StreamTokenType.thinkStart));
      expect(types, contains(StreamTokenType.thinkEnd));

      final textContent = tokens
          .where((t) => t.type == StreamTokenType.text)
          .map((t) => t.text)
          .join();
      expect(textContent, 'hi');
    });
  });
}
