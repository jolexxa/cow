import 'package:cow_brain/cow_brain.dart';
import 'package:cow_brain/src/adapters/extractors/json_tool_call_extractor.dart';
import 'package:cow_brain/src/adapters/stream_chunk.dart';
import 'package:cow_brain/src/adapters/stream_tokenizer.dart';
import 'package:cow_brain/src/adapters/universal_stream_parser.dart';
import 'package:cow_brain/src/core/model_output.dart';
import 'package:test/test.dart';

void main() {
  group('Qwen3StreamParser', () {
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
      expect((outputs[3] as OutputStepFinished).reason, FinishReason.stop);
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
      expect((outputs[2] as OutputToolCalls).calls.single.name, 'lookup');
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

      final textOutputs = outputs.whereType<OutputTextDelta>().toList();
      expect(textOutputs.map((output) => output.text).join(), 'Middle text');
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
        StreamChunk(
          text: '<tool_call>{"name":"b","arguments":{}}</tool_call>',
          tokenCountDelta: 0,
        ),
      ]);

      final outputs = await parser.parse(chunks).toList();

      final toolCallOutput = outputs.whereType<OutputToolCalls>().single;
      expect(toolCallOutput.calls, hasLength(1));
      expect(toolCallOutput.calls.first.name, 'a');

      // No text output after tool call.
      final textAfterTool = outputs
          .skipWhile((output) => output is! OutputToolCalls)
          .whereType<OutputTextDelta>();
      expect(textAfterTool, isEmpty);
    });

    test('handles empty stream', () async {
      const chunks = Stream<StreamChunk>.empty();

      final outputs = await parser.parse(chunks).toList();

      expect(outputs, hasLength(1));
      expect(outputs.single, isA<OutputStepFinished>());
    });

    test('handles reasoning with no content', () async {
      final chunks = Stream<StreamChunk>.fromIterable(const [
        StreamChunk(text: '<think></think>Done.', tokenCountDelta: 0),
      ]);

      final outputs = await parser.parse(chunks).toList();

      final textOutputs = outputs.whereType<OutputTextDelta>().toList();
      expect(textOutputs.map((output) => output.text).join(), 'Done.');
      expect(outputs.last, isA<OutputStepFinished>());
    });

    test('emits token updates when token count delta is provided', () async {
      final chunks = Stream<StreamChunk>.fromIterable(const [
        StreamChunk(text: 'Hello', tokenCountDelta: 3),
        StreamChunk(text: ' world', tokenCountDelta: 2),
      ]);

      final outputs = await parser.parse(chunks).toList();

      final tokenUpdates = outputs.whereType<OutputTokensGenerated>().toList();
      expect(tokenUpdates, hasLength(2));
      expect(tokenUpdates.first.count, 3);
      expect(tokenUpdates.last.count, 2);
    });
  });
}
