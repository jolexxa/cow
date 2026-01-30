import 'dart:async';

import 'package:cow/src/features/chat/domain/active_turn.dart';
import 'package:cow/src/features/chat/domain/models/chat_message.dart';
import 'package:cow/src/features/chat/domain/summary/summary_state.dart';
import 'package:cow_brain/cow_brain.dart';

final class SummaryController {
  SummaryController({
    required CowBrain brain,
    int wordThreshold = 40,
  }) : _brain = brain,
       _wordThreshold = wordThreshold;

  static const String _summaryPrompt =
      'You are a concise summarizer. Summarize the following reasoning so far '
      'in one sentence. Do not include step-by-step reasoning. Output a '
      'single, extremely concise sentence only.';
  static const String _userSummaryPrompt =
      'You are a concise summarizer. Summarize the user request in one '
      'sentence. Output a single, extremely concise sentence only.';
  static const String _placeholderText = 'Thinking...';
  static const AgentSettings _summarySettings = AgentSettings(
    safetyMarginTokens: 32,
    maxSteps: 2,
  );

  final CowBrain _brain;
  final int _wordThreshold;
  void Function()? emitSnapshot;

  String? _activeTurnId;
  bool _inFlight = false;
  int _requestId = 0;
  Completer<void>? _completer;
  final Map<String, SummaryState> _states = {};

  bool _isActiveTurn(ActiveTurn turn) => turn.responseId == _activeTurnId;

  SummaryState _stateFor(ActiveTurn turn) {
    return _states.putIfAbsent(turn.responseId, SummaryState.new);
  }

  Future<void> init({
    required LlamaRuntimeOptions runtimeOptions,
    required LlamaProfileId profile,
  }) async {
    await _brain.init(
      runtimeOptions: runtimeOptions,
      profile: profile,
      tools: const <ToolDefinition>[],
      settings: _summarySettings,
      enableReasoning: false,
    );
  }

  /// Starts tracking a new turn. Cancels any in-flight work for previous turns.
  void startTurn(String turnId) {
    if (_activeTurnId != turnId) {
      _cancelInFlight();
    }
    _activeTurnId = turnId;
  }

  void reset() {
    _brain.reset();
    _activeTurnId = null;
    _cancelInFlight();
    _states.clear();
  }

  void cancel() {
    _activeTurnId = null;
    _cancelInFlight();
  }

  void summarizeUserMessage(
    ActiveTurn turn,
    String text, {
    required bool enableReasoning,
  }) {
    if (!_isActiveTurn(turn)) {
      return;
    }
    final state = _stateFor(turn);
    if (state.frozen) {
      return;
    }
    if (!enableReasoning) {
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _ensureSummaryPlaceholder(turn);
    unawaited(
      _runSummaryForText(
        turn,
        state,
        trimmed,
        prompt: _userSummaryPrompt,
        markDirtyOnBusy: false,
      ),
    );
  }

  bool handleReasoningDelta(
    ActiveTurn turn,
    String text, {
    required bool enableReasoning,
  }) {
    if (!_isActiveTurn(turn)) {
      return false;
    }
    final state = _stateFor(turn);
    if (state.frozen) {
      return false;
    }
    if (!enableReasoning) {
      return false;
    }
    if (text.isEmpty) {
      return false;
    }
    final summaryCreated = _ensureSummaryPlaceholder(turn);
    state
      ..appendReasoning(text)
      ..wordsSinceSummary += _countWords(text);

    final sawNewline = text.contains('\n');
    final sawPeriod = text.contains('.');
    final shouldSummarize =
        sawNewline || (sawPeriod && state.wordsSinceSummary >= _wordThreshold);
    if (shouldSummarize) {
      state.dirty = true;
      if (!_inFlight) {
        state.wordsSinceSummary = 0;
      }
      unawaited(_runReasoningSummary(turn, state));
    }

    return summaryCreated;
  }

  Future<void> finalize(ActiveTurn turn) async {
    if (!_isActiveTurn(turn)) {
      return;
    }
    final state = _stateFor(turn);
    if (state.frozen) {
      return;
    }
    if (_completer != null) {
      await _completer!.future;
    }
    await _runReasoningSummary(turn, state, finalPass: true);
  }

  void freeze(ActiveTurn turn) {
    _stateFor(turn).freeze();
    _requestId += 1;
    _cancelInFlight();
  }

  Future<void> _runReasoningSummary(
    ActiveTurn turn,
    SummaryState state, {
    bool finalPass = false,
  }) async {
    if (!_isActiveTurn(turn)) {
      return;
    }
    if (state.frozen) {
      return;
    }
    if (_inFlight) {
      state.dirty = true;
      return;
    }
    if (!finalPass && !state.dirty) {
      return;
    }
    final reasoningText = state.reasoningText.trim();
    if (reasoningText.isEmpty) {
      return;
    }
    state.markClean();
    await _runSummaryForText(
      turn,
      state,
      reasoningText,
      prompt: _summaryPrompt,
      markDirtyOnBusy: true,
    );
  }

  Future<void> _runSummaryForText(
    ActiveTurn turn,
    SummaryState state,
    String text, {
    required String prompt,
    required bool markDirtyOnBusy,
  }) async {
    if (!_isActiveTurn(turn)) {
      return;
    }
    if (state.frozen) {
      return;
    }
    if (_inFlight) {
      if (markDirtyOnBusy) {
        state.dirty = true;
      }
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    _inFlight = true;
    state.dirty = false;
    _requestId += 1;
    final requestId = _requestId;
    final completer = Completer<void>();
    _completer = completer;

    try {
      final summary = await _generateSummary(trimmed, prompt: prompt);
      if (!_isActiveTurn(turn) || state.frozen || requestId != _requestId) {
        return;
      }
      _applySummary(turn, summary);
      if (_isActiveTurn(turn)) {
        emitSnapshot?.call();
      }
    } on Object catch (error) {
      if (!_isActiveTurn(turn) || state.frozen || requestId != _requestId) {
        return;
      }
      _applySummaryFailure(turn, error);
      if (_isActiveTurn(turn)) {
        emitSnapshot?.call();
      }
    } finally {
      _inFlight = false;
      if (!completer.isCompleted) {
        completer.complete();
      }
      if (state.dirty) {
        unawaited(_runReasoningSummary(turn, state));
      }
    }
  }

  Future<String> _generateSummary(
    String inputText, {
    required String prompt,
  }) async {
    _brain.reset();
    final buffer = StringBuffer();
    await for (final event in _brain.runTurn(
      userMessage: Message(
        role: Role.user,
        content: '$prompt\n\n$inputText',
      ),
      settings: _summarySettings,
      enableReasoning: false,
    )) {
      switch (event) {
        case AgentTextDelta(:final text):
          buffer.write(text);
        case AgentError(:final error):
          throw Exception(error);
        case AgentTurnFinished():
        case AgentStepFinished():
        case AgentStepStarted():
        case AgentReady():
        case AgentContextTrimmed():
        case AgentToolCalls():
        case AgentToolResult():
        case AgentTelemetryUpdate():
        case AgentReasoningDelta():
          break;
      }
    }
    return buffer.toString();
  }

  bool _ensureSummaryPlaceholder(ActiveTurn turn) {
    if (turn.summary != null) {
      return false;
    }
    turn.summary = ChatMessage.summary(
      _placeholderText,
      responseId: turn.responseId,
    );
    return true;
  }

  void _applySummary(ActiveTurn turn, String summary) {
    final normalized = _normalizeSummary(summary);
    if (normalized.isEmpty) {
      return;
    }
    final current =
        turn.summary ?? ChatMessage.summary('', responseId: turn.responseId);
    turn.summary = current.copyWithText(normalized);
  }

  void _applySummaryFailure(ActiveTurn turn, Object error) {
    final current =
        turn.summary ?? ChatMessage.summary('', responseId: turn.responseId);
    turn.summary = current.copyWithText('Summary unavailable.');
  }

  String _normalizeSummary(String summary) {
    final trimmed = summary.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
  }

  int _countWords(String text) {
    if (text.isEmpty) {
      return 0;
    }
    return RegExp(r'\b\w+\b').allMatches(text).length;
  }

  void _cancelInFlight() {
    _inFlight = false;
    final completer = _completer;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _completer = null;
  }
}
