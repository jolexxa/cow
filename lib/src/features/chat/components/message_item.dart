import 'package:cow/src/features/chat/components/message_item_layout.dart';
import 'package:cow/src/features/chat/state/models/chat_message.dart';
import 'package:nocterm/nocterm.dart';

class MessageItem extends StatelessComponent {
  const MessageItem({
    required this.message,
    this.showSpinner = false,
    this.showSender = true,
    super.key,
  });

  final ChatMessage message;
  final bool showSpinner;
  final bool showSender;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);

    final senderColor = switch (message.kind) {
      ChatMessageKind.system => Colors.red,
      ChatMessageKind.reasoning => Colors.cyan,
      ChatMessageKind.summary => Colors.gray,
      ChatMessageKind.user => Colors.brightGreen,
      ChatMessageKind.assistant => Colors.brightBlue,
    };

    final messageColor = switch (message.kind) {
      ChatMessageKind.system => Colors.brightRed,
      ChatMessageKind.reasoning => Colors.gray,
      ChatMessageKind.summary => Colors.gray,
      ChatMessageKind.user => Colors.green,
      ChatMessageKind.assistant => Colors.blue,
    };

    final messageColorAccent = switch (message.kind) {
      ChatMessageKind.system => theme.error,
      ChatMessageKind.reasoning => theme.outline,
      ChatMessageKind.summary => theme.warning,
      ChatMessageKind.user => theme.secondary,
      ChatMessageKind.assistant => theme.onSecondary,
    };

    return MessageItemLayout(
      senderLabel: message.sender,
      senderColor: senderColor,
      showSpinner: showSpinner,
      showSender: showSender,
      content: Row(
        children: [
          Expanded(
            child: MarkdownText(
              message.text,
              styleSheet: MarkdownStyleSheet(
                paragraphStyle: TextStyle(color: messageColor),
                boldStyle: TextStyle(
                  color: messageColorAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
