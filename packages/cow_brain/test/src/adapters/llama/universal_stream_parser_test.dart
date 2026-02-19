import 'package:cow_brain/src/adapters/extractors/json_tool_call_extractor.dart';
import 'package:cow_brain/src/adapters/stream_chunk.dart';
import 'package:cow_brain/src/adapters/stream_tokenizer.dart';
import 'package:cow_brain/src/adapters/universal_stream_parser.dart';
import 'package:cow_brain/src/core/model_output.dart';
import 'package:test/test.dart';

void main() {
  group('UniversalStreamParser', () {
    group('tag-based mode (default config)', () {
      late UniversalStreamParser parser;

      setUp(() {
        parser = UniversalStreamParser(
          config: StreamParserConfig(
            toolCallExtractor: const JsonToolCallExtractor(),
            tags: StreamTokenizer.defaultTags,
            supportsReasoning: true,
            enableFallbackToolParsing: false,
          ),
        );
      });

      test('parses reasoning, text, tool calls, and finish', () async {
        const toolJson = '{"id":"1","name":"search","arguments":{"query":"q"}}';
        final chunks = Stream<StreamChunk>.fromIterable(const [
          StreamChunk(
            text: '<think>Quiet plan.</think>',
            tokenCountDelta: 0,
          ),
          StreamChunk(
            text: 'Working...<tool_call>$toolJson</tool_call>',
            tokenCountDelta: 0,
          ),
        ]);

        final outputs = await parser.parse(chunks).toList();

        expect(outputs, hasLength(4));
        expect(outputs[0], isA<OutputReasoningDelta>());
        expect((outputs[0] as OutputReasoningDelta).text, 'Quiet plan.');
        expect(outputs[1], isA<OutputTextDelta>());
        expect((outputs[1] as OutputTextDelta).text, contains('Working...'));
        expect(outputs[2], isA<OutputToolCalls>());
        expect((outputs[2] as OutputToolCalls).calls.single.name, 'search');
        expect(outputs[3], isA<OutputStepFinished>());
      });

      test('handles tag boundaries across chunks', () async {
        final chunks = Stream<StreamChunk>.fromIterable(const [
          StreamChunk(text: '<think>Plan', tokenCountDelta: 0),
          StreamChunk(text: '.</think>Hi ', tokenCountDelta: 0),
          StreamChunk(
            text:
                '<tool_call>{"name":"lookup","arguments":{"id":42}}</tool_call>',
            tokenCountDelta: 0,
          ),
        ]);

        final outputs = await parser.parse(chunks).toList();

        expect(outputs, hasLength(4));
        expect(outputs[0], isA<OutputReasoningDelta>());
        expect((outputs[0] as OutputReasoningDelta).text, 'Plan.');
        expect(outputs[1], isA<OutputTextDelta>());
        expect((outputs[1] as OutputTextDelta).text, 'Hi ');
        expect(outputs[2], isA<OutputToolCalls>());
        expect(outputs[3], isA<OutputStepFinished>());
      });

      test('handles plain text without special tags', () async {
        final chunks = Stream<StreamChunk>.fromIterable(const [
          StreamChunk(text: 'Hello ', tokenCountDelta: 0),
          StreamChunk(text: 'world!', tokenCountDelta: 0),
        ]);

        final outputs = await parser.parse(chunks).toList();

        final textOutputs = outputs.whereType<OutputTextDelta>().toList();
        final combinedText = textOutputs.map((output) => output.text).join();
        expect(combinedText, 'Hello world!');
        expect(outputs.last, isA<OutputStepFinished>());
      });

      test('handles multiple reasoning blocks', () async {
        final chunks = Stream<StreamChunk>.fromIterable(const [
          StreamChunk(
            text:
                '<think>First thought.</think>Middle text<think>Second thought.</think>',
            tokenCountDelta: 0,
          ),
        ]);

        final outputs = await parser.parse(chunks).toList();

        final reasoningOutputs = outputs
            .whereType<OutputReasoningDelta>()
            .toList();
        expect(reasoningOutputs, hasLength(2));
        expect(reasoningOutputs[0].text, 'First thought.');
        expect(reasoningOutputs[1].text, 'Second thought.');
      });

      test('stops after tool calls', () async {
        final chunks = Stream<StreamChunk>.fromIterable(const [
          StreamChunk(
            text: '<tool_call>{"name":"a","arguments":{}}</tool_call>',
            tokenCountDelta: 0,
          ),
          StreamChunk(
            text: 'This text should be ignored',
            tokenCountDelta: 0,
          ),
        ]);

        final outputs = await parser.parse(chunks).toList();

        final toolCallOutput = outputs.whereType<OutputToolCalls>().single;
        expect(toolCallOutput.calls, hasLength(1));
        expect(toolCallOutput.calls.first.name, 'a');
      });

      test('handles empty stream', () async {
        const chunks = Stream<StreamChunk>.empty();

        final outputs = await parser.parse(chunks).toList();

        expect(outputs, hasLength(1));
        expect(outputs.single, isA<OutputStepFinished>());
      });

      test('emits token updates', () async {
        final chunks = Stream<StreamChunk>.fromIterable(const [
          StreamChunk(text: 'Hello', tokenCountDelta: 3),
          StreamChunk(text: ' world', tokenCountDelta: 2),
        ]);

        final outputs = await parser.parse(chunks).toList();

        final tokenUpdates = outputs
            .whereType<OutputTokensGenerated>()
            .toList();
        expect(tokenUpdates, hasLength(2));
        expect(tokenUpdates.first.count, 3);
        expect(tokenUpdates.last.count, 2);
      });
    });

    group('fallback tool parsing mode', () {
      late UniversalStreamParser parser;

      setUp(() {
        parser = UniversalStreamParser(
          config: StreamParserConfig(
            toolCallExtractor: const JsonToolCallExtractor(),
            tags: [],
            supportsReasoning: false,
            enableFallbackToolParsing: true,
          ),
        );
      });

      test('detects raw JSON tool call', () async {
        final chunks = Stream<StreamChunk>.fromIterable(const [
          StreamChunk(
            text: '{"name": "search", "arguments": {"q": "test"}}',
            tokenCountDelta: 0,
          ),
        ]);

        final outputs = await parser.parse(chunks).toList();

        expect(
          outputs.whereType<OutputToolCalls>(),
          hasLength(1),
        );
        expect(
          outputs.whereType<OutputToolCalls>().single.calls.single.name,
          'search',
        );
      });

      test('passes through text starting with a letter', () async {
        final chunks = Stream<StreamChunk>.fromIterable(const [
          StreamChunk(text: 'Hello world', tokenCountDelta: 0),
        ]);

        final outputs = await parser.parse(chunks).toList();

        final textOutputs = outputs.whereType<OutputTextDelta>().toList();
        expect(textOutputs.map((output) => output.text).join(), 'Hello world');
      });

      test('flushes as text when JSON is not a tool call', () async {
        final chunks = Stream<StreamChunk>.fromIterable(const [
          StreamChunk(
            text: '{"type": "not_a_tool", "value": 42}',
            tokenCountDelta: 0,
          ),
          StreamChunk(text: ' more text', tokenCountDelta: 0),
        ]);

        final outputs = await parser.parse(chunks).toList();

        final textOutputs = outputs.whereType<OutputTextDelta>().toList();
        final allText = textOutputs.map((output) => output.text).join();
        expect(allText, contains('not_a_tool'));
        expect(allText, contains('more text'));
      });

      test(
        'flushes whitespace-then-text without buffering to stream end',
        () async {
          final chunks = Stream<StreamChunk>.fromIterable(const [
            StreamChunk(text: ' \n', tokenCountDelta: 0),
            StreamChunk(text: 'Hello world', tokenCountDelta: 0),
          ]);

          final outputs = await parser.parse(chunks).toList();

          final textOutputs = outputs.whereType<OutputTextDelta>().toList();
          final allText = textOutputs.map((output) => output.text).join();
          expect(allText, contains('Hello world'));
          expect(outputs.whereType<OutputToolCalls>(), isEmpty);
        },
      );

      test('handles whitespace-then-JSON tool call', () async {
        final chunks = Stream<StreamChunk>.fromIterable(const [
          StreamChunk(text: '  \n', tokenCountDelta: 0),
          StreamChunk(
            text: '{"name": "search", "arguments": {"q": "test"}}',
            tokenCountDelta: 0,
          ),
        ]);

        final outputs = await parser.parse(chunks).toList();

        expect(outputs.whereType<OutputToolCalls>(), hasLength(1));
        expect(
          outputs.whereType<OutputToolCalls>().single.calls.single.name,
          'search',
        );
      });

      test('handles unbalanced braces on stream end', () async {
        final chunks = Stream<StreamChunk>.fromIterable(const [
          StreamChunk(
            text: '{"name": "search", "arguments": {"q": "test"',
            tokenCountDelta: 0,
          ),
        ]);

        final outputs = await parser.parse(chunks).toList();

        // Should flush as text since braces never balanced.
        final textOutputs = outputs.whereType<OutputTextDelta>().toList();
        expect(textOutputs, isNotEmpty);
      });
    });

    group('tool call without end tag (stream end)', () {
      test('parses tool call when stream ends mid-tool-call', () async {
        final parser = UniversalStreamParser(
          config: StreamParserConfig(
            toolCallExtractor: const JsonToolCallExtractor(),
            tags: [
              (tag: '[TOOL_CALLS]', type: StreamTokenType.toolStart),
            ],
            supportsReasoning: false,
            enableFallbackToolParsing: false,
          ),
        );

        final chunks = Stream<StreamChunk>.fromIterable(const [
          StreamChunk(
            text:
                '[TOOL_CALLS][{"name": "search", "arguments": {"q": "test"}}]',
            tokenCountDelta: 0,
          ),
        ]);

        final outputs = await parser.parse(chunks).toList();

        expect(outputs.whereType<OutputToolCalls>(), hasLength(1));
      });
    });

    group('mismatched/unexpected tags', () {
      test('ignores unexpected closing tags in normal mode', () async {
        final parser = UniversalStreamParser(
          config: StreamParserConfig(
            toolCallExtractor: const JsonToolCallExtractor(),
            tags: StreamTokenizer.defaultTags,
            supportsReasoning: true,
            enableFallbackToolParsing: false,
          ),
        );

        final chunks = Stream<StreamChunk>.fromIterable(const [
          StreamChunk(
            text: 'Hello</think>world</tool_call>!',
            tokenCountDelta: 0,
          ),
        ]);

        final outputs = await parser.parse(chunks).toList();

        final textOutputs = outputs.whereType<OutputTextDelta>().toList();
        final allText = textOutputs.map((output) => output.text).join();
        expect(allText, 'Helloworld!');
        expect(outputs.last, isA<OutputStepFinished>());
      });

      test('ignores unexpected tags inside reasoning mode', () async {
        final parser = UniversalStreamParser(
          config: StreamParserConfig(
            toolCallExtractor: const JsonToolCallExtractor(),
            tags: StreamTokenizer.defaultTags,
            supportsReasoning: true,
            enableFallbackToolParsing: false,
          ),
        );

        // Nested think start + tool tags inside reasoning should be ignored.
        final chunks = Stream<StreamChunk>.fromIterable(const [
          StreamChunk(
            text:
                '<think>Reasoning<think>nested<tool_call>junk</tool_call></think>Done',
            tokenCountDelta: 0,
          ),
        ]);

        final outputs = await parser.parse(chunks).toList();

        final reasoning = outputs
            .whereType<OutputReasoningDelta>()
            .map((output) => output.text)
            .join();
        expect(reasoning, contains('Reasoning'));
        final text = outputs
            .whereType<OutputTextDelta>()
            .map((output) => output.text)
            .join();
        expect(text, 'Done');
      });

      test('ignores unexpected tags inside tool call mode', () async {
        final parser = UniversalStreamParser(
          config: StreamParserConfig(
            toolCallExtractor: const JsonToolCallExtractor(),
            tags: StreamTokenizer.defaultTags,
            supportsReasoning: true,
            enableFallbackToolParsing: false,
          ),
        );

        // Think tags + nested tool_call start inside tool call should be
        // ignored; content still extracted on the real </tool_call>.
        final chunks = Stream<StreamChunk>.fromIterable(const [
          StreamChunk(
            text:
                '<tool_call><think></think><tool_call>{"name":"a","arguments":{}}</tool_call>',
            tokenCountDelta: 0,
          ),
        ]);

        final outputs = await parser.parse(chunks).toList();

        expect(outputs.whereType<OutputToolCalls>(), hasLength(1));
      });
    });

    group('StreamParserConfig invariants', () {
      test('asserts fallback requires empty tags', () {
        expect(
          () => StreamParserConfig(
            toolCallExtractor: const JsonToolCallExtractor(),
            tags: StreamTokenizer.defaultTags,
            supportsReasoning: false,
            enableFallbackToolParsing: true,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('allows fallback with empty tags', () {
        // Should not throw.
        StreamParserConfig(
          toolCallExtractor: const JsonToolCallExtractor(),
          tags: const [],
          supportsReasoning: false,
          enableFallbackToolParsing: true,
        );
      });
    });

    group('custom tags', () {
      test('works with Mistral-style tags', () async {
        // When [TOOL_CALLS] is a tag, the tokenizer strips it and the
        // remaining content goes to the extractor. Use JsonToolCallExtractor
        // since the content is a raw JSON array.
        final parser = UniversalStreamParser(
          config: StreamParserConfig(
            toolCallExtractor: const JsonToolCallExtractor(),
            tags: [
              (tag: '[TOOL_CALLS]', type: StreamTokenType.toolStart),
            ],
            supportsReasoning: false,
            enableFallbackToolParsing: false,
          ),
        );

        final chunks = Stream<StreamChunk>.fromIterable(const [
          StreamChunk(
            text:
                '[TOOL_CALLS] [{"name": "search", "arguments": {"q": "test"}}]',
            tokenCountDelta: 0,
          ),
        ]);

        final outputs = await parser.parse(chunks).toList();
        expect(outputs.whereType<OutputToolCalls>(), hasLength(1));
      });
    });
  });
}
