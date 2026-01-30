import 'dart:async';

import 'package:cow/src/features/chat/domain/active_turn.dart';
import 'package:cow/src/features/chat/domain/chat_state.dart';
import 'package:cow/src/features/chat/domain/models/chat_context_stats.dart';
import 'package:cow/src/features/chat/domain/models/chat_message.dart';
import 'package:cow/src/features/chat/domain/session_manager.dart';
import 'package:cow/src/features/chat/domain/summary/summary_controller.dart';
import 'package:cow/src/features/chat/domain/tool_executor.dart';
import 'package:cow/src/features/chat/domain/turn_runner.dart';
import 'package:cow_brain/cow_brain.dart';
import 'package:cow_model_manager/cow_model_manager.dart';

/// Chat session managing the conversation state and interactions.
class ChatSession {
  ChatSession({
    required this.toolRegistry,
    required this.llamaRuntimeOptions,
    required this.modelProfile,
    required this.summaryRuntimeOptions,
    required this.summaryModelProfile,
    required SessionManager session,
    required SummaryController summaryController,
    required ToolExecutor toolExecutor,
  }) : _session = session,
       _summaryController = summaryController,
       _toolExecutor = toolExecutor,
       _state = Uninitialized(enableReasoning: modelProfile.supportsReasoning);

  final ToolRegistry toolRegistry;
  final LlamaRuntimeOptions llamaRuntimeOptions;
  final ModelProfileSpec modelProfile;
  final LlamaRuntimeOptions summaryRuntimeOptions;
  final ModelProfileSpec summaryModelProfile;

  final SessionManager _session;
  final SummaryController _summaryController;
  final ToolExecutor _toolExecutor;

  final _controller = StreamController<ChatState>.broadcast();
  ChatState _state;
  AgentSettings? _agentSettings;
  var _responseCounter = 0;
  var _disposed = false;

  // ---------------------------------------------------------------------------
  // PUBLIC API
  // ---------------------------------------------------------------------------

  /// Current state.
  ChatState get state => _state;

  /// State stream for UI updates.
  Stream<ChatState> get stream => _controller.stream;

  /// Whether reasoning is enabled.
  bool get enableReasoning => _state.enableReasoning;

  /// Toggle reasoning on/off.
  void toggleReasoning() =>
      _emit(_state.withReasoning(value: !_state.enableReasoning));

  /// Initialize the session and load models.
  Future<void> start({List<ChatMessage> existingMessages = const []}) async {
    if (_state is! Uninitialized) return;

    final reasoning = _state.enableReasoning;
    _emit(Initializing(enableReasoning: reasoning));

    try {
      final agentSettings = _buildAgentSettings();
      await _session.initMain(
        runtimeOptions: llamaRuntimeOptions,
        profile: LlamaProfileId.values.byName(modelProfile.id),
        tools: toolRegistry.definitions,
        settings: agentSettings,
        enableReasoning: reasoning,
      );
      _agentSettings = agentSettings;

      await _session.initSummary(
        runtimeOptions: summaryRuntimeOptions,
        profile: LlamaProfileId.values.byName(summaryModelProfile.id),
      );

      final messages = [
        ...existingMessages,
        ChatMessage.alert('Model ready. Type a message to begin.'),
      ];
      _emit(Ready(messages: messages, enableReasoning: reasoning));
    } on Object catch (e) {
      _emit(_state.withError(e.toString(), existingMessages));
    }
  }

  /// Submit a user message.
  void submit(String message) {
    unawaited(_runSubmit(message));
  }

  /// Cancel the current turn (if active).
  void cancel() {
    final current = _state;
    if (current is! TurnActive) return;

    final turnId = current.turnId;
    if (turnId != null) {
      _session.main.cancel(turnId);
    }
    _summaryController.cancel();

    _emit(
      Ready(
        messages: current.messages,
        contextStats: current.contextStats,
        enableReasoning: current.enableReasoning,
      ),
    );
  }

  /// Clear all messages and reset the session.
  void clear() {
    _cancelIfActive();
    _session.main.reset();
    _summaryController.reset();
    _emit(Ready(messages: const [], enableReasoning: _state.enableReasoning));
  }

  /// Reset to ready state without clearing history.
  void reset() {
    final messages = _state.messages;
    _cancelIfActive();
    _session.main.reset();
    _summaryController.reset();
    _emit(
      Ready(
        messages: [...messages, ChatMessage.alert('Session reset.')],
        enableReasoning: _state.enableReasoning,
      ),
    );
  }

  /// Dispose of resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelIfActive();
    await _session.dispose();
    await _controller.close();
  }

  // ---------------------------------------------------------------------------
  // TURN EXECUTION
  // ---------------------------------------------------------------------------

  Future<void> _runSubmit(String message) async {
    try {
      final ready = _state;
      if (ready is! Ready) return;

      final text = message.trim();
      if (text.isEmpty) return;

      // Begin turn
      final turn = _beginTurn(text, ready);

      // Summarize user message
      _summaryController.emitSnapshot = _emitCurrentState;
      _summaryController.summarizeUserMessage(
        turn,
        text,
        enableReasoning: _state.enableReasoning,
      );

      // Stream agent events
      await _streamAgentEvents(turn, text);
    } finally {
      _summaryController.emitSnapshot = null;
    }
  }

  void _emitCurrentState() {
    if (_disposed) return;
    final current = _state;
    if (current is TurnActive) {
      _emit(current.rebuild());
    }
  }

  ActiveTurn _beginTurn(String text, Ready ready) {
    final responseId = _nextResponseId();
    final turn = ActiveTurn(
      ChatMessage.user(text, responseId: responseId),
      responseId: responseId,
    );

    _summaryController.startTurn(responseId);

    _emit(
      TurnActive(
        messages: ready.messages,
        turn: turn,
        turnPhase: const Preparing(),
        contextStats: ready.contextStats,
        enableReasoning: ready.enableReasoning,
      ),
    );

    return turn;
  }

  Future<void> _streamAgentEvents(ActiveTurn turn, String userMessage) async {
    final settings = _agentSettings;
    if (settings == null) {
      _handleError('Agent settings are missing.');
      return;
    }

    final runner = TurnRunner(turn);

    try {
      await for (final event in _session.main.runTurn(
        userMessage: Message(role: Role.user, content: userMessage),
        settings: settings,
        enableReasoning: _state.enableReasoning,
      )) {
        final current = _state;
        if (current is! TurnActive) break; // Cancelled

        // Let the phase handle the event and return the next phase
        final result = current.turnPhase.handle(event, current, runner);

        // Handle telemetry separately (updates stats, not phase)
        final stats = event is AgentTelemetryUpdate
            ? _statsFromTelemetry(event)
            : current.contextStats;

        // Handle reasoning summary
        final summaryChanged = _handleReasoningDelta(turn, event);

        if (result.changed || summaryChanged || stats != current.contextStats) {
          _emit(
            current.copyWith(
              turnPhase: result.phase,
              turnId: result.turnId ?? current.turnId,
              contextStats: stats,
            ),
          );
        }

        // Execute tool calls
        if (event is AgentToolCalls) {
          await _executeToolCalls(turn, event);
        }
      }

      _finalizeTurn();
    } on Object catch (e) {
      _handleError(e.toString());
    }
  }

  Future<void> _executeToolCalls(ActiveTurn turn, AgentToolCalls event) async {
    final current = _state;
    if (current is! TurnActive) return;

    _emit(current.copyWith(turnPhase: const ExecutingTool()));

    try {
      await _toolExecutor.execute(
        turnId: current.turnId ?? '',
        calls: event.calls,
      );
    } finally {
      final afterTool = _state;
      if (afterTool is TurnActive) {
        _emit(afterTool.copyWith(turnPhase: const Preparing()));
      }
    }
  }

  bool _handleReasoningDelta(ActiveTurn turn, AgentEvent event) {
    if (event is! AgentReasoningDelta) return false;
    if (!_state.enableReasoning) return false;
    if (event.text.isEmpty) return false;

    return _summaryController.handleReasoningDelta(
      turn,
      event.text,
      enableReasoning: _state.enableReasoning,
    );
  }

  void _finalizeTurn() {
    final current = _state;
    if (current is! TurnActive) return;

    _summaryController.freeze(current.turn);

    _emit(
      Ready(
        messages: current.messages,
        contextStats: current.contextStats,
        enableReasoning: current.enableReasoning,
      ),
    );
  }

  void _handleError(String error) {
    _emit(_state.withError(error, _state.messages));
  }

  void _emit(ChatState state) {
    if (_disposed) return;
    _state = state;
    _controller.add(state);
  }

  void _cancelIfActive() {
    final current = _state;
    if (current is TurnActive) {
      final turnId = current.turnId;
      if (turnId != null) {
        _session.main.cancel(turnId);
      }
      _summaryController.cancel();
    }
  }

  String _nextResponseId() {
    final value = _responseCounter;
    _responseCounter += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$value';
  }

  AgentSettings _buildAgentSettings() {
    return const AgentSettings(
      safetyMarginTokens: 64,
      maxSteps: 8,
    );
  }

  ChatContextStats _statsFromTelemetry(AgentTelemetryUpdate update) {
    return ChatContextStats(
      promptTokens: update.promptTokens,
      contextSize: update.contextSize,
      budgetTokens: update.budgetTokens,
      remainingTokens: update.remainingTokens,
      maxOutputTokens: update.maxOutputTokens,
      safetyMarginTokens: update.safetyMarginTokens,
    );
  }
}
