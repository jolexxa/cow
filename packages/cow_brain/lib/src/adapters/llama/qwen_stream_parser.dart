// Core contracts are evolving; we defer exhaustive API docs for now.

import 'dart:async';

import 'package:cow_brain/src/adapters/llama/llama_stream_chunk.dart';
import 'package:cow_brain/src/adapters/llama/llama_stream_parser.dart';
import 'package:cow_brain/src/adapters/llama/llama_tool_call_parser.dart';
import 'package:cow_brain/src/adapters/llama/stream_tokenizer.dart';
import 'package:cow_brain/src/core/model_output.dart';
import 'package:cow_brain/src/isolate/models.dart';

/// Parser state for the stream parser state machine.
enum _ParserState { normal, reasoning, toolCall }

/// Parses a stream of string chunks into model output events.
///
/// Uses [StreamTokenizer] to handle chunking/tag detection, then applies
/// a simple state machine to emit the appropriate [ModelOutput] events.
final class QwenStreamParser implements LlamaStreamParser {
  /// Creates a new stream parser with the given tool call parser.
  QwenStreamParser({required LlamaToolCallParser toolCallParser})
    : _toolCallParser = toolCallParser;

  final LlamaToolCallParser _toolCallParser;

  /// Parses a stream of string chunks into model output events.
  @override
  Stream<ModelOutput> parse(Stream<LlamaStreamChunk> chunks) {
    final output = StreamController<ModelOutput>();
    final textController = StreamController<String>();

    final tokenizer = StreamTokenizer();
    var state = _ParserState.normal;
    var toolBuffer = '';
    final toolCalls = <ToolCall>[];
    var stopAfterToolCalls = false;
    var outputClosed = false;

    Future<void> runTokenizer() async {
      await for (final token in tokenizer.tokenize(textController.stream)) {
        if (stopAfterToolCalls) break;

        switch ((state, token.type)) {
          // Normal mode.
          case (_ParserState.normal, StreamTokenType.text):
            output.add(OutputTextDelta(token.text!));

          case (_ParserState.normal, StreamTokenType.thinkStart):
            state = _ParserState.reasoning;

          case (_ParserState.normal, StreamTokenType.toolStart):
            state = _ParserState.toolCall;
            toolBuffer = '';

          // Reasoning mode.
          case (_ParserState.reasoning, StreamTokenType.text):
            output.add(OutputReasoningDelta(token.text!));

          case (_ParserState.reasoning, StreamTokenType.thinkEnd):
            state = _ParserState.normal;

          // Tool call mode.
          case (_ParserState.toolCall, StreamTokenType.text):
            toolBuffer += token.text!;

          case (_ParserState.toolCall, StreamTokenType.toolEnd):
            final parsed = _toolCallParser.parse(
              '<tool_call>$toolBuffer</tool_call>',
            );
            toolCalls.addAll(parsed.toolCalls);
            state = _ParserState.normal;
            toolBuffer = '';
            if (toolCalls.isNotEmpty) {
              stopAfterToolCalls = true;
            }

          // Ignore unexpected tokens (nested/mismatched tags).
          case _:
            break;
        }
      }

      if (toolCalls.isNotEmpty) {
        output.add(OutputToolCalls(List<ToolCall>.unmodifiable(toolCalls)));
      }

      output.add(const OutputStepFinished(FinishReason.stop));
      outputClosed = true;
      await output.close();
    }

    unawaited(runTokenizer());

    unawaited(() async {
      await for (final chunk in chunks) {
        if (outputClosed || stopAfterToolCalls) {
          continue;
        }
        if (chunk.tokenCountDelta > 0) {
          output.add(OutputTokensGenerated(chunk.tokenCountDelta));
        }
        if (chunk.text.isNotEmpty) {
          textController.add(chunk.text);
        }
      }
      await textController.close();
    }());

    return output.stream;
  }
}
