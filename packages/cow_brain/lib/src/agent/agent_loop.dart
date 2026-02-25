// The loop intentionally coordinates multiple contracts; docs can come later.
// `await for` keeps stream handling explicit and readable.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/agent/agent_runner.dart';
import 'package:cow_brain/src/agent/step_preparer.dart';
import 'package:cow_brain/src/agent/turn_emitter.dart';
import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/core/conversation.dart';
import 'package:cow_brain/src/core/llm_adapter.dart';
import 'package:cow_brain/src/core/model_output.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/tools/tool_registry.dart';
import 'package:cow_brain/src/utils/string_extensions.dart';

final class AgentLoop implements AgentRunner {
  AgentLoop({
    required LlmAdapter llm,
    required ToolRegistry tools,
    required ContextManager context,
    required this.contextSize,
    required this.maxOutputTokens,
    required this.temperature,
    this.sequenceId = 0,
  }) : _llm = llm,
       _tools = tools,
       _stepPreparer = StepPreparer(
         contextManager: context,
         contextSize: contextSize,
         maxOutputTokens: maxOutputTokens,
       );

  final LlmAdapter _llm;
  final ToolRegistry _tools;
  final StepPreparer _stepPreparer;

  /// Exposed for sequence forking — shared across sequences.
  LlmAdapter get llm => _llm;

  /// Exposed for sequence forking — shared across sequences.
  ToolRegistry get tools => _tools;

  /// Exposed for sequence forking — new agent loops need a fresh preparer.
  ContextManager get contextManager => _stepPreparer.contextManager;

  @override
  final int contextSize;
  @override
  final int maxOutputTokens;
  final double temperature;
  final int sequenceId;

  @override
  Stream<AgentEvent> runTurn(
    Conversation convo, {
    ToolExecutor? toolExecutor,
    bool Function()? shouldCancel,
    int maxSteps = 8,
    bool enableReasoning = true,
  }) async* {
    final emit = TurnEmitter(
      sequenceId: sequenceId,
      turnId: convo.beginTurn(),
    );
    while (emit.step < maxSteps) {
      _throwIfCancelled(shouldCancel);
      emit.step += 1;
      yield emit.stepStarted();

      final toolDefs = _tools.definitions;
      final prepared = _stepPreparer.prepare(
        messages: convo.messages,
        tools: toolDefs,
        enableReasoning: enableReasoning,
      );
      final slice = prepared.slice;

      yield emit.telemetry(slice);
      if (slice.droppedMessageCount > 0) {
        yield emit.contextTrimmed(slice.droppedMessageCount);
      }

      final remainingTokens = slice.remainingTokens;
      var generatedTokens = 0;
      final textBuffer = StringBuffer();
      final reasoningBuffer = StringBuffer();
      final toolCalls = <ToolCall>[];
      var finishReason = FinishReason.stop;

      try {
        await for (final output in _llm.next(
          messages: slice.messages,
          tools: toolDefs,
          enableReasoning: enableReasoning,
          config: LlmConfig(
            sequenceId: sequenceId,
            requiresReset: prepared.requiresReset,
            reusePrefixMessageCount: prepared.reusePrefixMessageCount,
          ),
        )) {
          switch (output) {
            case OutputTextDelta(:final text):
              if (_accumulate(textBuffer, text) case final delta?) {
                yield emit.textDelta(delta);
              }
            case OutputReasoningDelta(:final text):
              if (_accumulate(reasoningBuffer, text) case final delta?) {
                yield emit.reasoningDelta(delta);
              }
            case OutputToolCalls(:final calls):
              toolCalls.addAll(calls);
            case OutputTokensGenerated(:final count):
              if (count > 0) {
                generatedTokens += count;
                final updated = (remainingTokens - generatedTokens).clamp(
                  0,
                  remainingTokens,
                );
                yield emit.telemetry(slice, remainingOverride: updated);
              }
            case OutputStepFinished(:final reason):
              finishReason = reason;
          }
          _throwIfCancelled(shouldCancel);
        }

        final fullText = textBuffer.toString();
        final reasoningOrNull = reasoningBuffer.toStringOrNull();
        final textOrNull = textBuffer.toStringOrNull();

        if (toolCalls.isEmpty) {
          convo.appendAssistantText(fullText, reasoning: reasoningOrNull);
          yield emit.stepFinished(
            text: fullText,
            reasoning: reasoningOrNull,
            finishReason: finishReason,
          );
          yield emit.turnFinished(finishReason);
          return;
        }

        convo.appendAssistantToolCalls(
          toolCalls,
          preToolText: textOrNull,
          reasoning: reasoningOrNull,
        );
        yield emit.toolCalls(
          calls: toolCalls,
          preToolText: textOrNull,
          preToolReasoning: reasoningOrNull,
          finishReason: FinishReason.toolCalls,
        );

        _throwIfCancelled(shouldCancel);
        final executor = toolExecutor ?? _tools.executeAll;
        final results = await executor(toolCalls);
        for (final result in results) {
          convo.appendToolResult(result);
          yield emit.toolResult(result);
        }
      } on CancelledException {
        yield emit.turnFinished(FinishReason.cancelled);
        return;
      } on Object catch (error) {
        yield emit.error(error.toString());
        yield emit.turnFinished(FinishReason.error);
        return;
      }
    }

    yield emit.turnFinished(FinishReason.maxSteps);
  }

  /// Throws [CancelledException] if the cancel callback returns true.
  static void _throwIfCancelled(bool Function()? shouldCancel) {
    if (shouldCancel?.call() ?? false) {
      throw const CancelledException();
    }
  }

  /// Strips leading newlines on first delta, accumulates into [buffer],
  /// and returns the cleaned delta (or null if empty after stripping).
  static String? _accumulate(StringBuffer buffer, String text) {
    final delta = buffer.isEmpty ? text.stripLeadingNewlines() : text;
    if (delta.isEmpty) return null;
    buffer.write(delta);
    return delta;
  }
}
