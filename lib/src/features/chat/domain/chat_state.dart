import 'package:cow/src/features/chat/domain/active_turn.dart';
import 'package:cow/src/features/chat/domain/models/chat_context_stats.dart';
import 'package:cow/src/features/chat/domain/models/chat_message.dart';
import 'package:cow/src/features/chat/domain/models/chat_phase.dart';
import 'package:cow/src/features/chat/domain/turn_runner.dart';
import 'package:cow_brain/cow_brain.dart';

// =============================================================================
// TURN PHASE
// =============================================================================

/// Result of a phase handling an event.
final class PhaseResult {
  const PhaseResult(this.phase, {this.changed = false, this.turnId});

  final TurnPhase phase;
  final bool changed;
  final String? turnId;

  PhaseResult withTurnId(String id) =>
      PhaseResult(phase, changed: changed, turnId: id);
}

/// What the model is currently doing during an active turn.
/// Each phase handles events and transitions to the next phase.
sealed class TurnPhase {
  const TurnPhase();

  /// Handle an agent event, returning the next phase.
  PhaseResult handle(AgentEvent event, TurnActive state, TurnRunner runner) {
    // Capture turn ID if present
    String? turnId;
    if (event.turnId != null) {
      turnId = event.turnId;
    }

    // Let runner mutate turn state
    final changed = runner.handle(event);
    final result = _handleEvent(event, state);

    return PhaseResult(
      result.phase,
      changed: changed || result.changed,
      turnId: turnId,
    );
  }

  /// Override in subclasses for phase-specific transitions.
  PhaseResult _handleEvent(AgentEvent event, TurnActive state);

  /// For ChatPhase mapping.
  ChatPhase get chatPhase;
}

final class Preparing extends TurnPhase {
  const Preparing();

  @override
  PhaseResult _handleEvent(AgentEvent event, TurnActive state) {
    return switch (event) {
      AgentReasoningDelta(:final text)
          when state.enableReasoning && text.isNotEmpty =>
        const PhaseResult(Reasoning(), changed: true),
      AgentTextDelta(:final text) when text.isNotEmpty => const PhaseResult(
        Responding(),
        changed: true,
      ),
      _ => PhaseResult(this),
    };
  }

  @override
  ChatPhase get chatPhase => ChatPhase.idle;
}

final class Reasoning extends TurnPhase {
  const Reasoning();

  @override
  PhaseResult _handleEvent(AgentEvent event, TurnActive state) {
    return switch (event) {
      AgentTextDelta(:final text) when text.isNotEmpty => const PhaseResult(
        Responding(),
        changed: true,
      ),
      _ => PhaseResult(this),
    };
  }

  @override
  ChatPhase get chatPhase => ChatPhase.reasoning;
}

final class Responding extends TurnPhase {
  const Responding();

  @override
  PhaseResult _handleEvent(AgentEvent event, TurnActive state) {
    // Stay in responding until tool calls or turn end
    return PhaseResult(this);
  }

  @override
  ChatPhase get chatPhase => ChatPhase.responding;
}

final class ExecutingTool extends TurnPhase {
  const ExecutingTool();

  @override
  PhaseResult _handleEvent(AgentEvent event, TurnActive state) {
    // Tool execution is handled externally
    return PhaseResult(this);
  }

  @override
  ChatPhase get chatPhase => ChatPhase.executingTool;
}

// =============================================================================
// CHAT STATE
// =============================================================================

/// The session is always in exactly one of these states.
/// Pattern match exhaustively — no boolean flags needed.
sealed class ChatState {
  const ChatState({required this.enableReasoning});

  /// Whether reasoning is enabled (can be toggled at runtime).
  final bool enableReasoning;

  /// Messages for this state.
  List<ChatMessage> get messages;

  /// Context stats for this state.
  ChatContextStats? get stats;

  /// Whether the session is loading models.
  bool get loading => false;

  /// Whether a turn is currently active.
  bool get generating => false;

  /// Error message if in failed state.
  String? get error => null;

  /// Current phase derived from state.
  ChatPhase get phase;

  /// Visible messages (excludes reasoning).
  List<ChatMessage> get visibleMessages {
    return messages
        .where((message) => !message.isReasoning)
        .toList(growable: false);
  }

  /// Reasoning messages only.
  List<ChatMessage> get reasoningMessages {
    return messages
        .where(
          (message) => message.isReasoning && message.text.trim().isNotEmpty,
        )
        .toList(growable: false);
  }

  /// Status string for UI display.
  String get status {
    return switch (phase) {
      ChatPhase.loading => 'Loading',
      ChatPhase.error => 'Error',
      ChatPhase.executingTool => 'Tools',
      ChatPhase.reasoning => 'Reasoning',
      ChatPhase.responding => 'Responding',
      ChatPhase.idle => 'Ready',
    };
  }

  /// Return a copy with reasoning toggled.
  ChatState withReasoning({required bool value});

  /// Return a Failed state with the given error.
  ChatState withError(String error, List<ChatMessage> messages);
}

/// Initial state before start() is called.
final class Uninitialized extends ChatState {
  const Uninitialized({super.enableReasoning = true});

  @override
  List<ChatMessage> get messages => const [];

  @override
  ChatContextStats? get stats => null;

  @override
  ChatPhase get phase => ChatPhase.idle;

  @override
  ChatState withReasoning({required bool value}) =>
      Uninitialized(enableReasoning: value);

  @override
  ChatState withError(String error, List<ChatMessage> messages) => Failed(
    messages: messages,
    errorMessage: error,
    enableReasoning: enableReasoning,
  );
}

/// Loading models and preparing the session.
final class Initializing extends ChatState {
  const Initializing({super.enableReasoning = true});

  @override
  List<ChatMessage> get messages => [ChatMessage.alert('Loading model...')];

  @override
  ChatContextStats? get stats => null;

  @override
  bool get loading => true;

  @override
  ChatPhase get phase => ChatPhase.loading;

  @override
  ChatState withReasoning({required bool value}) =>
      Initializing(enableReasoning: value);

  @override
  ChatState withError(String error, List<ChatMessage> messages) => Failed(
    messages: messages,
    errorMessage: error,
    enableReasoning: enableReasoning,
  );
}

/// Ready to accept user input.
final class Ready extends ChatState {
  const Ready({
    required List<ChatMessage> messages,
    this.contextStats,
    super.enableReasoning = true,
  }) : _messages = messages;

  final List<ChatMessage> _messages;
  final ChatContextStats? contextStats;

  @override
  List<ChatMessage> get messages => _messages;

  @override
  ChatContextStats? get stats => contextStats;

  @override
  ChatPhase get phase => ChatPhase.idle;

  @override
  ChatState withReasoning({required bool value}) => Ready(
    messages: _messages,
    contextStats: contextStats,
    enableReasoning: value,
  );

  @override
  ChatState withError(String error, List<ChatMessage> messages) => Failed(
    messages: messages,
    errorMessage: error,
    contextStats: contextStats,
    enableReasoning: enableReasoning,
  );
}

/// Processing a turn (user message → model response).
final class TurnActive extends ChatState {
  const TurnActive({
    required List<ChatMessage> messages,
    required this.turn,
    required this.turnPhase,
    this.turnId,
    this.contextStats,
    super.enableReasoning = true,
  }) : _messages = messages;

  /// Committed message history (excludes current turn).
  final List<ChatMessage> _messages;

  /// The in-progress turn being built.
  final ActiveTurn turn;

  /// Current turn phase.
  final TurnPhase turnPhase;

  /// Backend turn ID for cancellation.
  final String? turnId;

  /// Latest context stats from telemetry.
  final ChatContextStats? contextStats;

  @override
  List<ChatMessage> get messages => [..._messages, ...turn.toMessages()];

  @override
  ChatContextStats? get stats => contextStats;

  @override
  bool get generating => true;

  @override
  ChatPhase get phase => turnPhase.chatPhase;

  /// Committed messages only (excludes current turn).
  List<ChatMessage> get committedMessages => _messages;

  TurnActive copyWith({
    List<ChatMessage>? messages,
    ActiveTurn? turn,
    TurnPhase? turnPhase,
    String? turnId,
    ChatContextStats? contextStats,
    bool? enableReasoning,
  }) {
    return TurnActive(
      messages: messages ?? _messages,
      turn: turn ?? this.turn,
      turnPhase: turnPhase ?? this.turnPhase,
      turnId: turnId ?? this.turnId,
      contextStats: contextStats ?? this.contextStats,
      enableReasoning: enableReasoning ?? this.enableReasoning,
    );
  }

  /// For emitting state changes without modifications.
  TurnActive rebuild() => copyWith();

  @override
  ChatState withReasoning({required bool value}) =>
      copyWith(enableReasoning: value);

  @override
  ChatState withError(String error, List<ChatMessage> messages) => Failed(
    messages: messages,
    errorMessage: error,
    contextStats: contextStats,
    enableReasoning: enableReasoning,
  );
}

/// Something went wrong. Can retry or reset.
final class Failed extends ChatState {
  const Failed({
    required List<ChatMessage> messages,
    required this.errorMessage,
    this.contextStats,
    super.enableReasoning = true,
  }) : _messages = messages;

  final List<ChatMessage> _messages;
  final String errorMessage;
  final ChatContextStats? contextStats;

  @override
  List<ChatMessage> get messages => _messages;

  @override
  ChatContextStats? get stats => contextStats;

  @override
  String? get error => errorMessage;

  @override
  ChatPhase get phase => ChatPhase.error;

  @override
  ChatState withReasoning({required bool value}) => Failed(
    messages: _messages,
    errorMessage: errorMessage,
    contextStats: contextStats,
    enableReasoning: value,
  );

  @override
  ChatState withError(String error, List<ChatMessage> messages) => Failed(
    messages: messages,
    errorMessage: error,
    contextStats: contextStats,
    enableReasoning: enableReasoning,
  );
}
