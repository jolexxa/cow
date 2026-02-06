import 'dart:async';

import 'package:nocterm/nocterm.dart';

/// Common layout for message-like rows in the chat.
///
/// Provides consistent structure: padding, spinner slot, sender label, content.
class MessageItemLayout extends StatelessComponent {
  const MessageItemLayout({
    required this.senderLabel,
    required this.senderColor,
    required this.content,
    this.showSpinner = false,
    this.showSender = true,
    super.key,
  });

  final String senderLabel;
  final Color senderColor;
  final Component content;
  final bool showSpinner;
  final bool showSender;

  static const int senderWidth = 7;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final paddedLabel = senderLabel.padLeft(senderWidth);

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
            '$paddedLabel:',
            style: TextStyle(color: senderColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 1),
        ],
        Expanded(child: content),
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
