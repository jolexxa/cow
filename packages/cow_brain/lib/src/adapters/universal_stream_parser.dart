// Core contracts are evolving; we defer exhaustive API docs for now.
// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:cow_brain/src/adapters/stream_chunk.dart';
import 'package:cow_brain/src/adapters/stream_parser.dart';
import 'package:cow_brain/src/adapters/stream_tokenizer.dart';
import 'package:cow_brain/src/adapters/tool_call_extractor.dart';
import 'package:cow_brain/src/core/model_output.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/utils/json_brace_utils.dart';

/// Configuration for the [UniversalStreamParser].
final class StreamParserConfig {
  StreamParserConfig({
    required this.toolCallExtractor,
    required this.tags,
    required this.supportsReasoning,
    required this.enableFallbackToolParsing,
  }) {
    if (enableFallbackToolParsing && tags.isNotEmpty) {
      throw ArgumentError(
        'Fallback tool parsing requires empty tags — tagless models only.',
      );
    }
  }

  final ToolCallExtractor toolCallExtractor;

  /// Tag definitions for the stream tokenizer.
  final List<TagDefinition> tags;

  final bool supportsReasoning;

  /// When true, the parser will attempt to detect raw JSON/pythonic tool calls
  /// that aren't wrapped in tags. Only used for models like Llama 3 that don't
  /// use wrapper tags.
  ///
  /// Requires [tags] to be empty — the tokenizer produces only text tokens
  /// in this mode, so fallback buffering never needs to handle tag events.
  final bool enableFallbackToolParsing;
}

enum _ParserState { normal, reasoning, toolCall }

/// Universal stream parser for all supported model families.
///
/// Same state machine architecture, but parameterized via [StreamParserConfig].
final class UniversalStreamParser implements StreamParser {
  UniversalStreamParser({required this.config});

  final StreamParserConfig config;

  @override
  Stream<ModelOutput> parse(Stream<StreamChunk> chunks) {
    final output = StreamController<ModelOutput>();
    final textController = StreamController<String>();

    final tokenizer = StreamTokenizer(tags: config.tags);
    var state = _ParserState.normal;
    var toolBuffer = '';
    final toolCalls = <ToolCall>[];
    var stopAfterToolCalls = false;
    var outputClosed = false;
    final fallbackActive = config.enableFallbackToolParsing;
    var fallbackDisabled = false;
    var fallbackBuffering = false;

    Future<void> runTokenizer() async {
      await for (final token in tokenizer.tokenize(textController.stream)) {
        if (stopAfterToolCalls) break;

        switch (state) {
          case _ParserState.normal:
            switch (token.type) {
              case StreamTokenType.text:
                final text = token.text!;

                // Continue buffering if we're already in fallback mode.
                if (fallbackBuffering) {
                  toolBuffer += text;
                  if (_resolveBuffer(
                    toolBuffer,
                    toolCalls,
                    output,
                    config.toolCallExtractor,
                    onFlush: () {
                      fallbackDisabled = true;
                      fallbackBuffering = false;
                      toolBuffer = '';
                    },
                    onToolCalls: () {
                      fallbackBuffering = false;
                      toolBuffer = '';
                      stopAfterToolCalls = true;
                    },
                  )) {
                    break;
                  }
                  break;
                }

                // First text token: check if fallback buffering should start.
                if (fallbackActive && !fallbackDisabled) {
                  final trimmed = text.trimLeft();
                  if (trimmed.isEmpty ||
                      trimmed.codeUnitAt(0) == 0x7B /* { */ ||
                      trimmed.codeUnitAt(0) == 0x5B /* [ */ ) {
                    fallbackBuffering = true;
                    toolBuffer = text;
                    break;
                  }
                  // Starts with a regular character — disable fallback.
                  fallbackDisabled = true;
                }
                output.add(OutputTextDelta(text));

              case StreamTokenType.thinkStart:
                if (config.supportsReasoning) {
                  state = _ParserState.reasoning;
                }

              case StreamTokenType.toolStart:
                state = _ParserState.toolCall;
                toolBuffer = '';

              case StreamTokenType.thinkEnd:
              case StreamTokenType.toolEnd:
                break; // Ignore unexpected closing tags in normal mode.
            }

          case _ParserState.reasoning:
            switch (token.type) {
              case StreamTokenType.text:
                output.add(OutputReasoningDelta(token.text!));
              case StreamTokenType.thinkEnd:
                state = _ParserState.normal;
              case StreamTokenType.thinkStart:
              case StreamTokenType.toolStart:
              case StreamTokenType.toolEnd:
                break;
            }

          case _ParserState.toolCall:
            switch (token.type) {
              case StreamTokenType.text:
                toolBuffer += token.text!;
              case StreamTokenType.toolEnd:
                final parsed = config.toolCallExtractor.extract(toolBuffer);
                toolCalls.addAll(parsed);
                state = _ParserState.normal;
                toolBuffer = '';
                if (toolCalls.isNotEmpty) {
                  stopAfterToolCalls = true;
                }
              case StreamTokenType.thinkStart:
              case StreamTokenType.thinkEnd:
              case StreamTokenType.toolStart:
                break;
            }
        }
      }

      // Handle stream end.
      if (state == _ParserState.toolCall && toolBuffer.isNotEmpty) {
        // Model ended mid-tool-call (e.g. Mistral with no end tag).
        final parsed = config.toolCallExtractor.extract(toolBuffer);
        toolCalls.addAll(parsed);
      }

      if (fallbackBuffering && toolBuffer.isNotEmpty) {
        // Try to parse whatever we have.
        final parsed = config.toolCallExtractor.extract(toolBuffer.trim());
        if (parsed.isNotEmpty) {
          toolCalls.addAll(parsed);
        } else {
          output.add(OutputTextDelta(toolBuffer));
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

  /// Tries to resolve the fallback buffer. Returns true if the buffer was
  /// resolved (either as tool calls or flushed as text), false if still
  /// waiting for more data.
  static bool _resolveBuffer(
    String buffer,
    List<ToolCall> toolCalls,
    StreamController<ModelOutput> output,
    ToolCallExtractor extractor, {
    required void Function() onFlush,
    required void Function() onToolCalls,
  }) {
    // If buffer has non-whitespace content that doesn't start
    // with a brace, it's not a tool call — bail out.
    final trimmed = buffer.trimLeft();
    if (trimmed.isNotEmpty) {
      final fc = trimmed.codeUnitAt(0);
      if (fc != 0x7B /* { */ && fc != 0x5B /* [ */ ) {
        output.add(OutputTextDelta(buffer));
        onFlush();
        return true;
      }
    }

    // Check if braces are balanced.
    if (areBracesBalanced(buffer)) {
      final parsed = extractor.extract(buffer.trim());
      if (parsed.isNotEmpty) {
        toolCalls.addAll(parsed);
        onToolCalls();
      } else {
        output.add(OutputTextDelta(buffer));
        onFlush();
      }
      return true;
    }

    return false;
  }
}
