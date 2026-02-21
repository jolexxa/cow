import 'package:cow/src/features/chat/state/chat_data.dart';
import 'package:cow/src/features/chat/state/models/chat_message.dart';
import 'package:cow/src/features/chat/state/summary/summary_data.dart';
import 'package:cow/src/features/chat/state/summary/summary_input.dart';
import 'package:cow/src/features/chat/state/summary/summary_output.dart';
import 'package:logic_blocks/logic_blocks.dart';

/// Constants used for summary generation.
abstract final class SummaryConstants {
  static const String reasoningPrompt =
      'You are a concise summarizer. Summarize the following reasoning so far '
      'in one sentence. Do not include step-by-step reasoning. Output a '
      'single, extremely concise sentence only.';

  static const String userMessagePrompt =
      'You are a concise summarizer. Summarize the user request in one '
      'sentence. Output a single, extremely concise sentence only.';

  static const String placeholderText = 'Thinking...';

  static const String failureText = 'Summary unavailable.';
}

/// Base state for the summary logic block.
sealed class SummaryState extends StateLogic<SummaryState> {
  SummaryData get data => get<SummaryData>();
  ChatData get chatData => get<ChatData>();

  int? get turnId => data.turnId;

  int countWords(String text) {
    if (text.isEmpty) return 0;
    return RegExp(r'\b\w+\b').allMatches(text).length;
  }

  /// Normalizes summary text by trimming and collapsing whitespace.
  String normalizeSummary(String summary) {
    final trimmed = summary.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Updates the active turn's summary directly on ChatData.
  void updateSummary(String? text) {
    final turnId = data.turnId;
    if (turnId == null) return;
    chatData.activeTurn?.summary = text == null
        ? null
        : ChatMessage.summary(text, responseId: turnId);
    output(const SummaryChanged());
  }
}

/// No active turn.
final class IdleState extends SummaryState {
  IdleState() {
    on<StartTurn>((input) {
      data
        ..resetTurnData()
        ..turnId = input.turnId;
      return to<AccumulatingState>();
    });

    on<ResetSummary>((_) => toSelf());
    on<CancelSummary>((_) => toSelf());

    // Ignore everything else in idle
    on<ReasoningDelta>((_) => toSelf());
    on<SummarizeUserMessage>((_) => toSelf());
    on<Finalize>((_) => toSelf());
    on<Freeze>((_) => toSelf());
    on<SummaryComplete>((_) => toSelf());
    on<SummaryFailed>((_) => toSelf());
  }
}

/// Receiving deltas, not summarizing.
final class AccumulatingState extends SummaryState {
  AccumulatingState({this.wordThreshold = 40}) {
    on<ReasoningDelta>(_onReasoningDelta);
    on<SummarizeUserMessage>(_onSummarizeUserMessage);
    on<Finalize>(_onFinalize);
    on<Freeze>((_) => to<FrozenState>());
    on<CancelSummary>((_) {
      data.resetTurnData();
      return to<IdleState>();
    });
    on<ResetSummary>((_) {
      data.resetTurnData();
      return to<IdleState>();
    });
    on<StartTurn>((input) {
      data
        ..resetTurnData()
        ..turnId = input.turnId;
      return toSelf();
    });

    // Ignore async results in this state
    on<SummaryComplete>((_) => toSelf());
    on<SummaryFailed>((_) => toSelf());
  }

  final int wordThreshold;

  Transition _onReasoningDelta(ReasoningDelta input) {
    final text = input.text;
    if (text.isEmpty) return toSelf();

    data
      ..reasoningBuffer.write(text)
      ..wordsSinceSummary += countWords(text);

    final sawNewline = text.contains('\n');
    final sawPeriod = text.contains('.');
    final shouldSummarize =
        sawNewline || (sawPeriod && data.wordsSinceSummary >= wordThreshold);

    if (shouldSummarize) {
      data.wordsSinceSummary = 0;
      final reasoningText = data.reasoningText.trim();
      if (reasoningText.isNotEmpty) {
        final requestId = data.nextRequestId();
        // Don't overwrite existing summary with placeholder - keep showing
        // whatever we have until the new summary is ready.
        if (data.summaryText == null) {
          data.summaryText = SummaryConstants.placeholderText;
          updateSummary(data.summaryText);
        }
        output(
          RunSummaryRequested(
            text: reasoningText,
            prompt: SummaryConstants.reasoningPrompt,
            requestId: requestId,
          ),
        );
        return to<SummarizingState>();
      }
    }

    return toSelf();
  }

  Transition _onSummarizeUserMessage(SummarizeUserMessage input) {
    if (!input.enableReasoning) return toSelf();

    final trimmed = input.text.trim();
    if (trimmed.isEmpty) return toSelf();

    final requestId = data.nextRequestId();
    data.summaryText = SummaryConstants.placeholderText;
    updateSummary(data.summaryText);
    output(
      RunSummaryRequested(
        text: trimmed,
        prompt: SummaryConstants.userMessagePrompt,
        requestId: requestId,
      ),
    );
    return to<SummarizingState>();
  }

  Transition _onFinalize(Finalize input) {
    final reasoningText = data.reasoningText.trim();
    if (reasoningText.isEmpty) return toSelf();

    final requestId = data.nextRequestId();
    output(
      RunSummaryRequested(
        text: reasoningText,
        prompt: SummaryConstants.reasoningPrompt,
        requestId: requestId,
      ),
    );
    return to<SummarizingState>();
  }
}

/// Async summary in flight (can still receive deltas).
final class SummarizingState extends SummaryState {
  SummarizingState({this.wordThreshold = 40}) {
    on<ReasoningDelta>(_onReasoningDelta);
    on<SummaryComplete>(_onSummaryComplete);
    on<SummaryFailed>(_onSummaryFailed);
    on<Freeze>((_) => to<FrozenState>());
    on<CancelSummary>((_) {
      data.resetTurnData();
      return to<IdleState>();
    });
    on<ResetSummary>((_) {
      data.resetTurnData();
      return to<IdleState>();
    });
    on<StartTurn>((input) {
      // New turn started, reset and go to accumulating
      data
        ..resetTurnData()
        ..turnId = input.turnId;
      return to<AccumulatingState>();
    });

    // Ignore these in summarizing state
    on<SummarizeUserMessage>((_) => toSelf());
    on<Finalize>((_) => toSelf());
  }

  final int wordThreshold;

  Transition _onReasoningDelta(ReasoningDelta input) {
    final text = input.text;
    if (text.isEmpty) return toSelf();

    data
      ..reasoningBuffer.write(text)
      ..wordsSinceSummary += countWords(text)
      ..dirty = true;

    return toSelf();
  }

  Transition _onSummaryComplete(SummaryComplete input) {
    if (input.requestId != data.requestId) {
      // Stale request, ignore
      return toSelf();
    }

    final normalized = normalizeSummary(input.summary);
    if (normalized.isNotEmpty) {
      data.summaryText = normalized;
    }
    updateSummary(data.summaryText);

    if (data.dirty) {
      return _continueSummarizing();
    }

    return to<AccumulatingState>();
  }

  Transition _onSummaryFailed(SummaryFailed input) {
    if (input.requestId != data.requestId) {
      // Stale request, ignore
      return toSelf();
    }

    data.summaryText = SummaryConstants.failureText;
    updateSummary(data.summaryText);

    if (data.dirty) {
      return _continueSummarizing();
    }

    return to<AccumulatingState>();
  }

  Transition _continueSummarizing() {
    data
      ..dirty = false
      ..wordsSinceSummary = 0;

    final reasoningText = data.reasoningText.trim();
    if (reasoningText.isEmpty) {
      return to<AccumulatingState>();
    }

    final requestId = data.nextRequestId();
    output(
      RunSummaryRequested(
        text: reasoningText,
        prompt: SummaryConstants.reasoningPrompt,
        requestId: requestId,
      ),
    );
    return toSelf();
  }
}

/// Turn done, ignore all inputs except Reset/StartTurn.
final class FrozenState extends SummaryState {
  FrozenState() {
    on<ResetSummary>((_) {
      data.resetTurnData();
      return to<IdleState>();
    });

    on<StartTurn>((input) {
      data
        ..resetTurnData()
        ..turnId = input.turnId;
      return to<AccumulatingState>();
    });

    // Ignore everything else
    on<ReasoningDelta>((_) => toSelf());
    on<SummarizeUserMessage>((_) => toSelf());
    on<Finalize>((_) => toSelf());
    on<Freeze>((_) => toSelf());
    on<CancelSummary>((_) => toSelf());
    on<SummaryComplete>((_) => toSelf());
    on<SummaryFailed>((_) => toSelf());
  }
}

/// The summary logic block.
final class SummaryLogic extends LogicBlock<SummaryState> {
  SummaryLogic({required ChatData chatData, int wordThreshold = 40}) {
    set(chatData);
    set(SummaryData());
    set(IdleState());
    set(AccumulatingState(wordThreshold: wordThreshold));
    set(SummarizingState(wordThreshold: wordThreshold));
    set(FrozenState());
  }

  @override
  Transition getInitialState() => to<IdleState>();
}
