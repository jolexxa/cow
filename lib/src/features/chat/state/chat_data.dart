import 'package:cow/src/features/chat/state/active_turn.dart';
import 'package:cow/src/features/chat/state/models/chat_context_stats.dart';
import 'package:cow/src/features/chat/state/models/chat_message.dart';
import 'package:cow_brain/cow_brain.dart';

/// Mutable data container stored on the logic block blackboard.
///
/// Shared across all states — states read and write this directly.
final class ChatData {
  /// Committed message history.
  List<ChatMessage> messages = [];

  /// Latest context stats from telemetry.
  ChatContextStats? stats;

  /// The in-progress turn (non-null only during TurnActive).
  ActiveTurn? activeTurn;

  /// Whether reasoning is enabled.
  bool enableReasoning = true;

  /// Whether tools are currently being executed.
  bool executingTool = false;

  /// Backend turn ID for cancellation.
  String? turnId;

  /// Error message (non-null only in Failed state).
  String? error;

  /// Agent settings for the current session. Set during initialization,
  /// guaranteed non-null after ModelsLoaded.
  late AgentSettings agentSettings;
}
