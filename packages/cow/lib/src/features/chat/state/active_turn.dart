import 'package:cow/src/features/chat/state/models/chat_message.dart';
import 'package:cow_brain/cow_brain.dart';

final class ActiveTurn {
  ActiveTurn(this.user, {required this.responseId})
    : assistant = ChatMessage.assistant('', responseId: responseId);

  final ChatMessage user;
  final int responseId;
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

  bool applyEvent(AgentEvent event) {
    return switch (event) {
      AgentTextDelta(:final text) when text.isNotEmpty => () {
        appendAssistant(text);
        return true;
      }(),
      AgentReasoningDelta(:final text) when text.isNotEmpty => () {
        appendReasoning(text);
        return true;
      }(),
      AgentContextTrimmed(:final droppedMessageCount) => () {
        addAlert('Context trimmed: dropped $droppedMessageCount message(s).');
        return true;
      }(),
      AgentToolCalls(:final calls) => () {
        final names = calls.map((call) => call.name).toList();
        final label = names.length == 1 ? 'tool' : 'tools';
        setToolAlert('Calling $label: ${names.join(', ')}');
        return true;
      }(),
      AgentToolResult(:final result) when result.isError => () {
        final errorText = result.errorMessage ?? 'Unknown tool error.';
        addAlert('Tool ${result.name} failed: $errorText');
        return true;
      }(),
      AgentError(:final error) => throw Exception(error),
      _ => false,
    };
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
