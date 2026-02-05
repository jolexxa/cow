// The loop intentionally coordinates multiple contracts; docs can come later.
// `await for` keeps stream handling explicit and readable.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/agent/agent_runner.dart';
import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/core/conversation.dart';
import 'package:cow_brain/src/core/llm_adapter.dart';
import 'package:cow_brain/src/core/model_output.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/tools/tool_registry.dart';

final class AgentLoop implements AgentRunner {
  AgentLoop({
    required LlmAdapter llm,
    required ToolRegistry tools,
    required ContextManager context,
    required this.contextSize,
    required this.maxOutputTokens,
    required this.temperature,
  }) : _llm = llm,
       _tools = tools,
       _context = context;

  final LlmAdapter _llm;
  final ToolRegistry _tools;
  final ContextManager _context;

  @override
  final int contextSize;
  @override
  final int maxOutputTokens;
  final double temperature;

  // Tracks previous reasoning state to detect toggles requiring context reset.
  bool? _lastEnableReasoning;

  @override
  Stream<AgentEvent> runTurn(
    Conversation convo, {
    ToolExecutor? toolExecutor,
    bool Function()? shouldCancel,
    int maxSteps = 8,
    bool enableReasoning = true,
  }) async* {
    final turnId = convo.beginTurn();
    var steps = 0;
    var systemApplied = convo.systemApplied;
    ContextSlice? previousSlice;

    while (steps < maxSteps) {
      if (shouldCancel?.call() ?? false) {
        throw const CancelledException();
      }
      steps += 1;
      yield AgentStepStarted(turnId: turnId, step: steps);

      final toolDefs = _tools.definitions;
      var slice = _context.prepare(
        messages: convo.messages,
        tools: toolDefs,
        contextSize: contextSize,
        maxOutputTokens: maxOutputTokens,
        systemApplied: systemApplied,
        previousSlice: previousSlice,
      );

      var requiresReset = slice.requiresReset;
      var reusePrefixMessageCount = slice.reusePrefixMessageCount;

      // Force reset if reasoning toggle changed (prompt format differs).
      if (_lastEnableReasoning != null &&
          _lastEnableReasoning != enableReasoning) {
        requiresReset = true;
        reusePrefixMessageCount = 0;
      }
      _lastEnableReasoning = enableReasoning;

      // If the slice is incompatible with the previous one, we need to reset
      // the native context and ensure the system prompt is re-applied.
      if (requiresReset && systemApplied) {
        systemApplied = false;
        slice = _context.prepare(
          messages: convo.messages,
          tools: toolDefs,
          contextSize: contextSize,
          maxOutputTokens: maxOutputTokens,
          systemApplied: systemApplied,
        );
        requiresReset = true;
        reusePrefixMessageCount = 0;
        previousSlice = null;
      }

      previousSlice = slice;
      final remainingTokens = slice.remainingTokens;
      var generatedTokens = 0;
      yield AgentTelemetryUpdate(
        turnId: turnId,
        step: steps,
        promptTokens: slice.estimatedPromptTokens,
        budgetTokens: slice.budgetTokens,
        remainingTokens: slice.remainingTokens,
        contextSize: slice.contextSize,
        maxOutputTokens: slice.maxOutputTokens,
        safetyMarginTokens: slice.safetyMarginTokens,
      );
      if (slice.droppedMessageCount > 0) {
        yield AgentContextTrimmed(
          turnId: turnId,
          step: steps,
          droppedMessageCount: slice.droppedMessageCount,
        );
      }

      final textBuffer = StringBuffer();
      final reasoningBuffer = StringBuffer();
      final toolCalls = <ToolCall>[];
      var finishReason = FinishReason.stop;

      try {
        await for (final output in _llm.next(
          messages: slice.messages,
          tools: toolDefs,
          systemApplied: systemApplied,
          enableReasoning: enableReasoning,
          config: LlmConfig(
            requiresReset: requiresReset,
            reusePrefixMessageCount: reusePrefixMessageCount,
          ),
        )) {
          switch (output) {
            case OutputTextDelta(:final text):
              var delta = text;
              if (textBuffer.isEmpty) {
                delta = _stripLeadingNewline(delta);
              }
              if (delta.isEmpty) {
                break;
              }
              textBuffer.write(delta);
              yield AgentTextDelta(turnId: turnId, step: steps, text: delta);
            case OutputReasoningDelta(:final text):
              var delta = text;
              if (reasoningBuffer.isEmpty) {
                delta = _stripLeadingNewline(delta);
              }
              if (delta.isEmpty) {
                break;
              }
              reasoningBuffer.write(delta);
              yield AgentReasoningDelta(
                turnId: turnId,
                step: steps,
                text: delta,
              );
            case OutputToolCalls(:final calls):
              toolCalls.addAll(calls);
            case OutputTokensGenerated(:final count):
              if (count > 0) {
                generatedTokens += count;
                var updatedRemaining = remainingTokens - generatedTokens;
                if (updatedRemaining < 0) {
                  updatedRemaining = 0;
                } else if (updatedRemaining > remainingTokens) {
                  updatedRemaining = remainingTokens;
                }
                yield AgentTelemetryUpdate(
                  turnId: turnId,
                  step: steps,
                  promptTokens: slice.estimatedPromptTokens,
                  budgetTokens: slice.budgetTokens,
                  remainingTokens: updatedRemaining,
                  contextSize: slice.contextSize,
                  maxOutputTokens: slice.maxOutputTokens,
                  safetyMarginTokens: slice.safetyMarginTokens,
                );
              }
            case OutputStepFinished(:final reason):
              finishReason = reason;
          }
          if (shouldCancel?.call() ?? false) {
            throw const CancelledException();
          }
        }

        final fullText = textBuffer.toString();
        final reasoning = reasoningBuffer.toString();
        final reasoningOrNull = reasoning.isEmpty ? null : reasoning;
        final textOrNull = fullText.isEmpty ? null : fullText;

        // The system prompt has now been applied to the native context.
        systemApplied = true;
        convo.setSystemApplied(value: true);

        if (toolCalls.isEmpty) {
          convo.appendAssistantText(fullText, reasoning: reasoningOrNull);
          yield AgentStepFinished(
            turnId: turnId,
            step: steps,
            text: fullText,
            reasoning: reasoningOrNull,
            finishReason: finishReason,
          );
          yield AgentTurnFinished(
            turnId: turnId,
            step: steps,
            finishReason: finishReason,
          );
          return;
        }

        convo.appendAssistantToolCalls(
          toolCalls,
          preToolText: textOrNull,
          reasoning: reasoningOrNull,
        );
        yield AgentToolCalls(
          turnId: turnId,
          step: steps,
          calls: toolCalls,
          preToolText: textOrNull,
          preToolReasoning: reasoningOrNull,
          finishReason: FinishReason.toolCalls,
        );

        if (shouldCancel?.call() ?? false) {
          throw const CancelledException();
        }
        final executor = toolExecutor ?? _tools.executeAll;
        final results = await executor(toolCalls);
        for (final result in results) {
          convo.appendToolResult(result);
          yield AgentToolResult(turnId: turnId, step: steps, result: result);
        }
      } on CancelledException {
        convo.setSystemApplied(value: systemApplied);
        yield AgentTurnFinished(
          turnId: turnId,
          step: steps,
          finishReason: FinishReason.cancelled,
        );
        return;
      } on Object catch (error) {
        convo.setSystemApplied(value: systemApplied);
        yield AgentError(turnId: turnId, step: steps, error: error.toString());
        yield AgentTurnFinished(
          turnId: turnId,
          step: steps,
          finishReason: FinishReason.error,
        );
        return;
      }
    }

    yield AgentTurnFinished(
      turnId: turnId,
      step: steps,
      finishReason: FinishReason.maxSteps,
    );
  }

  String _stripLeadingNewline(String value) {
    var start = 0;
    while (start < value.length) {
      final char = value[start];
      if (char == '\n' || char == '\r') {
        start += 1;
      } else {
        break;
      }
    }
    return start == 0 ? value : value.substring(start);
  }
}
