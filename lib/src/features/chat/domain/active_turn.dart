import 'package:cow/src/features/chat/domain/models/chat_message.dart';

final class ActiveTurn {
  ActiveTurn(this.user, {required this.responseId})
    : assistant = ChatMessage.assistant('', responseId: responseId);

  final ChatMessage user;
  final String responseId;
  ChatMessage assistant;
  ChatMessage? reasoning;
  ChatMessage? summary;
  final List<ChatMessage> alerts = <ChatMessage>[];
  int? _toolAlertIndex;

  void appendAssistant(String delta) {
    assistant = assistant.append(delta);
  }

  void appendReasoning(String delta) {
    final current =
        reasoning ?? ChatMessage.reasoning('', responseId: responseId);
    reasoning = current.copyWithText('${current.text}$delta');
  }

  void setToolAlert(String text) {
    final index = _toolAlertIndex;
    if (index != null && index < alerts.length) {
      alerts[index] = alerts[index].copyWithText(text);
      return;
    }
    _toolAlertIndex = alerts.length;
    alerts.add(ChatMessage.alert(text, responseId: responseId));
  }

  void addAlert(String text) {
    alerts.add(ChatMessage.alert(text, responseId: responseId));
  }

  List<ChatMessage> toMessages() {
    return <ChatMessage>[
      user,
      ?summary,
      ?reasoning,
      ...alerts,
      assistant,
    ];
  }
}
