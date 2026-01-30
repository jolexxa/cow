import 'package:cow/src/features/chat/domain/chat_state.dart';
import 'package:cow/src/features/chat/domain/models/chat_message.dart';
import 'package:meta/meta.dart';

/// Events for the ChatBloc.
sealed class ChatEvent {
  const ChatEvent();
}

/// Internal event when session emits a new state.
@internal
final class ChatSessionStateChanged extends ChatEvent {
  const ChatSessionStateChanged(this.state);

  final ChatState state;
}

/// Start the chat session and load models.
final class ChatStarted extends ChatEvent {
  const ChatStarted({this.existingMessages = const []});

  final List<ChatMessage> existingMessages;
}

/// Submit a user message to the model.
final class ChatMessageSubmitted extends ChatEvent {
  const ChatMessageSubmitted(this.message);

  final String message;
}

/// Cancel the current turn.
final class ChatCancelled extends ChatEvent {
  const ChatCancelled();
}

/// Reset the session and clear history.
final class ChatReset extends ChatEvent {
  const ChatReset();
}

/// Toggle reasoning on/off.
final class ChatReasoningToggled extends ChatEvent {
  const ChatReasoningToggled();
}
