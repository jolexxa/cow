import 'package:cow/src/features/chat/components/message_item_layout.dart';
import 'package:cow/src/features/chat/state/models/model_load_progress.dart';
import 'package:nocterm/nocterm.dart';

class LoadingProgressItem extends StatelessComponent {
  const LoadingProgressItem({required this.progress, super.key});

  final ModelLoadProgress progress;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final percent = (progress.currentProgress * 100).toStringAsFixed(0);

    return MessageItemLayout(
      senderLabel: 'System',
      senderColor: Colors.red,
      showSpinner: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Loading ${progress.currentModelName} '
            '(${progress.currentModelIndex}/${progress.totalModels})',
            style: const TextStyle(color: Colors.brightRed),
          ),
          Row(
            children: [
              Expanded(
                child: ProgressBar(
                  value: progress.currentProgress,
                  borderStyle: ProgressBarBorderStyle.single,
                  valueColor: theme.warning,
                ),
              ),
              const SizedBox(width: 1),
              Text(
                '$percent%',
                style: TextStyle(color: theme.secondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
