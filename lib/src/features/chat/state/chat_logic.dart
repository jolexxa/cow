import 'package:cow/src/features/chat/state/active_turn.dart';
import 'package:cow/src/features/chat/state/chat_data.dart';
import 'package:cow/src/features/chat/state/chat_input.dart';
import 'package:cow/src/features/chat/state/chat_output.dart';
import 'package:cow/src/features/chat/state/models/chat_context_stats.dart';
import 'package:cow/src/features/chat/state/models/chat_message.dart';
import 'package:cow/src/features/chat/state/models/chat_phase.dart';
import 'package:cow/src/features/chat/state/models/model_load_progress.dart';
import 'package:cow_brain/cow_brain.dart';
import 'package:logic_blocks/logic_blocks.dart';

/// Base state for the chat logic block.
///
/// Exposes blackboard data via getters so the UI can consume these states
/// directly without a separate data-class layer.
sealed class ChatState extends StateLogic<ChatState> {
  ChatData get data => get<ChatData>();
  CowBrain get brain => get<CowBrain>();

  bool get enableReasoning => data.enableReasoning;
  List<ChatMessage> get messages => data.messages;
  ChatContextStats? get stats => data.stats;
  bool get loading => false;
  bool get generating => false;
  String? get error => null;
  ChatPhase get phase;

  /// Registers the common ToggleReasoning handler.
  void onToggleReasoning() {
    on<ToggleReasoning>((_) {
      data.enableReasoning = !data.enableReasoning;
      output(const StateUpdated());
      return toSelf();
    });
  }

  List<ChatMessage> get visibleMessages {
    return messages
        .where((message) => !message.isReasoning)
        .toList(growable: false);
  }

  List<ChatMessage> get reasoningMessages {
    return messages
        .where(
          (message) => message.isReasoning && message.text.trim().isNotEmpty,
        )
        .toList(growable: false);
  }

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
}

final class UninitializedState extends ChatState {
  UninitializedState() {
    on<Start>((input) {
      data.messages = [...input.existingMessages];
      output(LoadModelsRequested(enableReasoning: data.enableReasoning));
      return to<InitializingState>();
    });

    onToggleReasoning();
  }

  @override
  ChatPhase get phase => ChatPhase.idle;
}

final class InitializingState extends ChatState {
  InitializingState() {
    on<SetTotalModels>((input) {
      data.totalModelsToLoad = input.count;
      return toSelf();
    });

    on<ModelLoadProgressUpdate>((input) {
      data.modelLoadProgress = ModelLoadProgress(
        currentModelIndex: input.currentModel,
        totalModels: input.totalModels,
        currentProgress: input.progress,
        currentModelName: input.modelName,
      );
      output(const StateUpdated());
      return toSelf();
    });

    on<ModelLoaded>((input) {
      data.loadedModels[input.role] = input.model;

      // When all models loaded, request brain initialization.
      if (data.loadedModels.length == data.totalModelsToLoad) {
        output(
          InitializeBrainsRequested(
            models: Map.of(data.loadedModels),
            enableReasoning: data.enableReasoning,
          ),
        );
      }
      return toSelf();
    });

    on<BrainsInitialized>((input) {
      data
        ..modelLoadProgress = null
        ..loadedModels = {}
        ..agentSettings = input.settings
        ..messages.add(
          ChatMessage.alert('Model ready. Type a message to begin.'),
        );
      return to<ReadyState>();
    });

    on<ModelsLoadFailed>((input) {
      data.error = input.error;
      return to<FailedState>();
    });

    onToggleReasoning();
  }

  @override
  List<ChatMessage> get messages => const [];

  @override
  bool get loading => true;

  @override
  ChatPhase get phase => ChatPhase.loading;
}

final class ReadyState extends ChatState {
  ReadyState() {
    onEnter(() {
      output(const StateUpdated());
    });

    on<Submit>((input) {
      if (input.message.isEmpty) return toSelf();

      final turn = ActiveTurn(
        ChatMessage.user(input.message, responseId: input.responseId),
        responseId: input.responseId,
      );
      data
        ..activeTurn = turn
        ..executingTool = false
        ..turnId = null;

      output(StartSummaryTurnRequested(responseId: input.responseId));
      output(
        SummarizeUserMessageRequested(
          turn: turn,
          text: input.message,
          enableReasoning: data.enableReasoning,
        ),
      );
      output(
        StartTurnRequested(
          userMessage: input.message,
          enableReasoning: data.enableReasoning,
        ),
      );
      return to<TurnActiveState>();
    });

    on<Clear>((_) {
      data
        ..messages = []
        ..stats = null
        ..error = null;
      brain.reset();
      output(const ResetSummaryRequested());
      output(const StateUpdated());
      return toSelf();
    });

    on<Reset>((_) {
      data
        ..error = null
        ..messages = [...data.messages, ChatMessage.alert('Session reset.')];
      brain.reset();
      output(const ResetSummaryRequested());
      output(const StateUpdated());
      return toSelf();
    });

    onToggleReasoning();
  }

  @override
  ChatPhase get phase => ChatPhase.idle;
}

final class TurnActiveState extends ChatState {
  TurnActiveState() {
    on<AgentEventReceived>((input) {
      final event = input.event;
      turn.applyEvent(event);

      if (event.turnId != null) {
        data.turnId = event.turnId;
      }

      if (event is AgentTelemetryUpdate) {
        data.stats = ChatContextStats(
          promptTokens: event.promptTokens,
          contextSize: event.contextSize,
          budgetTokens: event.budgetTokens,
          remainingTokens: event.remainingTokens,
          maxOutputTokens: event.maxOutputTokens,
          safetyMarginTokens: event.safetyMarginTokens,
        );
      }

      if (event is AgentReasoningDelta && event.text.isNotEmpty) {
        output(ReasoningSummaryRequested(turn: turn, text: event.text));
      }

      if (event is AgentToolCalls) {
        data.executingTool = true;
        output(
          ExecuteToolCallsRequested(
            event: event,
            turnId: data.turnId!,
          ),
        );
      }

      output(const StateUpdated());
      return toSelf();
    });

    on<ToolCallsComplete>((_) {
      data.executingTool = false;
      output(const StateUpdated());
      return toSelf();
    });

    on<TurnFinalized>((_) {
      final activeTurn = turn;
      _commitTurn();
      output(FreezeSummaryRequested(turn: activeTurn));
      return to<ReadyState>();
    });

    on<TurnError>((input) {
      _commitTurn();
      data.error = input.error;
      return to<FailedState>();
    });

    on<Cancel>((_) {
      final turnId = data.turnId;
      if (turnId != null) brain.cancel(turnId);
      output(const CancelSummaryRequested());
      _commitTurn();
      return to<ReadyState>();
    });

    on<Clear>((_) {
      final turnId = data.turnId;
      if (turnId != null) brain.cancel(turnId);
      data
        ..messages = []
        ..activeTurn = null
        ..executingTool = false
        ..turnId = null
        ..stats = null
        ..error = null;
      brain.reset();
      output(const ResetSummaryRequested());
      return to<ReadyState>();
    });

    on<Reset>((_) {
      final turnId = data.turnId;
      if (turnId != null) brain.cancel(turnId);
      _commitTurn();
      data.messages = [...data.messages, ChatMessage.alert('Session reset.')];
      brain.reset();
      output(const ResetSummaryRequested());
      return to<ReadyState>();
    });

    on<Dispose>((_) {
      final turnId = data.turnId;
      if (turnId != null) brain.cancel(turnId);
      output(const CancelSummaryRequested());
      return toSelf();
    });

    onToggleReasoning();
  }

  /// Non-null in TurnActiveState — crashes if violated (bug).
  ActiveTurn get turn => data.activeTurn!;

  @override
  List<ChatMessage> get messages => [...data.messages, ...turn.toMessages()];

  @override
  bool get generating => true;

  @override
  ChatPhase get phase {
    if (data.executingTool) return ChatPhase.executingTool;
    if (turn.assistant.text.isNotEmpty) return ChatPhase.responding;
    if (turn.reasoning != null) return ChatPhase.reasoning;
    return ChatPhase.idle;
  }

  void _commitTurn() {
    data
      ..messages = [...data.messages, ...turn.toMessages()]
      ..activeTurn = null
      ..executingTool = false
      ..turnId = null;
  }
}

final class FailedState extends ChatState {
  FailedState() {
    on<Clear>((_) {
      data
        ..messages = []
        ..stats = null
        ..error = null;
      brain.reset();
      output(const ResetSummaryRequested());
      return to<ReadyState>();
    });

    on<Reset>((_) {
      data
        ..messages = [...data.messages, ChatMessage.alert('Session reset.')]
        ..error = null;
      brain.reset();
      output(const ResetSummaryRequested());
      return to<ReadyState>();
    });

    onToggleReasoning();
  }

  @override
  List<ChatMessage> get messages => [
    ...data.messages,
    if (data.error != null) ChatMessage.alert(data.error!),
  ];

  @override
  String? get error => data.error;

  @override
  ChatPhase get phase => ChatPhase.error;
}

final class ChatLogic extends LogicBlock<ChatState> {
  ChatLogic({required ChatData chatData, required CowBrain brain}) {
    set(chatData);
    set(brain);
    set(UninitializedState());
    set(InitializingState());
    set(ReadyState());
    set(TurnActiveState());
    set(FailedState());
  }

  @override
  Transition getInitialState() => to<UninitializedState>();
}
