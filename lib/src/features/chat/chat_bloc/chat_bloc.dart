import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:cow/src/features/chat/chat_bloc/chat_event.dart';
import 'package:cow/src/features/chat/domain/domain.dart';

export 'chat_event.dart';

/// Thin wrapper around [ChatSession] for use with `BlocProvider`.
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(this._session) : super(_session.state) {
    on<ChatStarted>(_onStarted);
    on<ChatMessageSubmitted>(_onMessageSubmitted);
    on<ChatCancelled>(_onCancelled);
    on<ChatReset>(_onReset);
    on<ChatReasoningToggled>(_onReasoningToggled);
    on<ChatSessionStateChanged>(_onSessionStateChanged);

    _subscription = _session.stream.listen(
      (state) => add(ChatSessionStateChanged(state)),
    );
  }

  final ChatSession _session;
  late final StreamSubscription<ChatState> _subscription;

  /// Whether reasoning is enabled.
  bool get enableReasoning => _session.enableReasoning;

  Future<void> _onStarted(
    ChatStarted event,
    Emitter<ChatState> emit,
  ) async {
    await _session.start(existingMessages: event.existingMessages);
  }

  void _onMessageSubmitted(
    ChatMessageSubmitted event,
    Emitter<ChatState> emit,
  ) {
    _session.submit(event.message);
  }

  void _onCancelled(
    ChatCancelled event,
    Emitter<ChatState> emit,
  ) {
    _session.cancel();
  }

  void _onReset(
    ChatReset event,
    Emitter<ChatState> emit,
  ) {
    _session
      ..clear()
      ..reset();
  }

  void _onReasoningToggled(
    ChatReasoningToggled event,
    Emitter<ChatState> emit,
  ) {
    _session.toggleReasoning();
  }

  void _onSessionStateChanged(
    ChatSessionStateChanged event,
    Emitter<ChatState> emit,
  ) {
    emit(event.state);
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _session.dispose();
    return super.close();
  }
}
