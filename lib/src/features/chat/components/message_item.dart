import 'dart:async';

import 'package:cow/src/features/chat/domain/models/chat_message.dart';
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

  static const int _senderWidth = 7;

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

    final senderLabel = message.sender.padLeft(_senderWidth);

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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 1),
        if (showSpinner)
          const InlineSpinner()
        else
          Text(' ', style: TextStyle(color: theme.secondary)),
        const SizedBox(width: 1),
        if (showSender) ...[
          Text(
            '$senderLabel:',
            style: TextStyle(color: senderColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 1),
        ],
        Expanded(
          child: Row(
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
        ),
      ],
    );
  }
}

class InlineSpinner extends StatefulComponent {
  const InlineSpinner({super.key});

  @override
  State<InlineSpinner> createState() => _InlineSpinnerState();
}

class _InlineSpinnerState extends State<InlineSpinner> {
  static const List<String> _frames = <String>['|', '/', '-', r'\'];
  static const Duration _interval = Duration(milliseconds: 120);

  Timer? _timer;
  var _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_interval, (_) {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % _frames.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Text(
      _frames[_index],
      style: TextStyle(color: theme.secondary),
    );
  }
}
