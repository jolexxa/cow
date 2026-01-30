import 'dart:async';

import 'package:blocterm/blocterm.dart';
import 'package:cow/src/features/chat/chat.dart';
import 'package:cow/src/features/startup/startup_bloc/startup_bloc.dart';
import 'package:cow/src/features/startup/startup_bloc/startup_event.dart';
import 'package:cow/src/features/startup/startup_bloc/startup_state.dart';
import 'package:nocterm/nocterm.dart';

class AppStartupView extends StatefulComponent {
  const AppStartupView({super.key});

  @override
  State<AppStartupView> createState() => _AppStartupViewState();
}

class _AppStartupViewState extends State<AppStartupView> {
  @override
  void initState() {
    super.initState();
    unawaited(
      Future<void>.delayed(Duration.zero).then((_) {
        if (!mounted) return;
        BlocProvider.of<StartupBloc>(
          context,
          listen: false,
        ).add(const AppStartupStarted());
      }),
    );
  }

  @override
  Component build(BuildContext context) {
    return BlocBuilder<StartupBloc, StartupState>(
      builder: (context, state) {
        if (state.status == StartupStatus.ready) {
          return const ChatPageView();
        }
        return const StartupPage();
      },
    );
  }
}

class StartupPage extends StatefulComponent {
  const StartupPage({super.key});

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  final ScrollController _scrollController = ScrollController();

  bool _handleKeyEvent(KeyboardEvent event, StartupBloc bloc) {
    if (event.matches(LogicalKey.keyC, ctrl: true)) {
      if (bloc.state.status == StartupStatus.downloading ||
          bloc.state.status == StartupStatus.checking) {
        bloc.add(const AppStartupCancelled());
      } else {
        TerminalBinding.instance.requestShutdown();
      }
      return true;
    }
    if (event.matches(LogicalKey.enter)) {
      if (bloc.state.status == StartupStatus.awaitingInput) {
        bloc.add(const AppStartupContinue());
        return true;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final bloc = BlocProvider.of<StartupBloc>(context, listen: false);

    return BlocBuilder<StartupBloc, StartupState>(
      builder: (context, state) {
        final progress = state.progress;
        final totalReceivedBytes = _sumReceivedBytes(state.files);
        final totalBytes = _totalBytesOrNull(state.files);
        final totalProgressText = _formatTotalProgressText(
          totalReceivedBytes,
          totalBytes,
        );
        final speedText = progress == null
            ? '--'
            : _formatSpeed(progress.speedBytesPerSecond);

        final filesText = state.totalFiles == 0
            ? ''
            : 'Files: ${state.completedFiles}/${state.totalFiles}';
        final showTotal = state.totalFiles > 1;

        final statusLine = switch (state.status) {
          StartupStatus.checking => 'Checking models...',
          StartupStatus.downloading => _downloadStatusLine(
            filesText,
            speedText,
          ),
          StartupStatus.awaitingInput => 'Models installed.',
          StartupStatus.error => 'Download failed',
          StartupStatus.ready => 'Ready',
        };

        final totalPercent = switch (totalBytes ?? 0) {
          <= 0 => null,
          _ => _clamp01(totalReceivedBytes / totalBytes!),
        };

        final fileRows = _buildFileRows(state.files, theme);

        return Container(
          padding: const EdgeInsets.all(1),
          color: theme.background,
          child: Focusable(
            focused: true,
            onKeyEvent: (event) => _handleKeyEvent(event, bloc),
            child: Container(
              color: theme.background,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 76),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: theme.surface,
                      border: BoxBorder.all(
                        style: BoxBorderStyle.double,
                      ),
                      title: BorderTitle(
                        text: 'Welcome to Cow',
                        alignment: TitleAlignment.center,
                        style: TextStyle(
                          color: theme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildHeader(theme),
                        Expanded(
                          child: _buildScrollableBody(
                            theme: theme,
                            state: state,
                            statusLine: statusLine,
                            fileRows: fileRows,
                            showTotal: showTotal,
                            totalProgressText: totalProgressText,
                            totalPercent: totalPercent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Component _buildHeader(TuiThemeData theme) {
    return Text(
      '[Ctrl+C] Cancel download',
      style: TextStyle(color: theme.error),
      textAlign: TextAlign.center,
    );
  }

  Component _buildScrollableBody({
    required TuiThemeData theme,
    required StartupState state,
    required String statusLine,
    required List<Component> fileRows,
    required bool showTotal,
    required String totalProgressText,
    required double? totalPercent,
  }) {
    return Container(
      padding: const EdgeInsets.only(right: 1),
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scrollController,
          keyboardScrollable: true,
          child: Column(
            children: [
              const SizedBox(height: 1),
              _buildStatus(theme: theme, state: state, statusLine: statusLine),
              const SizedBox(height: 1),
              _buildFileList(
                theme: theme,
                fileRows: fileRows,
                showTotal: showTotal,
                totalProgressText: totalProgressText,
                totalPercent: totalPercent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Component _buildStatus({
    required TuiThemeData theme,
    required StartupState state,
    required String statusLine,
  }) {
    return Column(
      children: [
        Text(
          'Cow is downloading required files.',
          style: TextStyle(color: theme.onSurface),
          textAlign: TextAlign.center,
        ),
        Text(
          'Models are stored in ~/.cow/models.',
          style: TextStyle(color: theme.secondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 1),
        Text(
          statusLine,
          style: TextStyle(color: theme.primary),
          textAlign: TextAlign.center,
        ),
        if (state.status == StartupStatus.awaitingInput)
          Text(
            'Press Enter to continue',
            style: TextStyle(
              color: theme.success,
            ),
            textAlign: TextAlign.center,
          ),
        if (state.status == StartupStatus.error && state.error != null)
          Text(
            state.error!,
            style: TextStyle(color: theme.error),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  Component _buildFileList({
    required TuiThemeData theme,
    required List<Component> fileRows,
    required bool showTotal,
    required String totalProgressText,
    required double? totalPercent,
  }) {
    if (fileRows.isEmpty && !showTotal) {
      return const SizedBox();
    }
    return Column(
      children: [
        if (fileRows.isNotEmpty) Column(children: fileRows),
        if (showTotal)
          _buildTotalRow(
            theme: theme,
            totalProgressText: totalProgressText,
            totalPercent: totalPercent,
          ),
        const SizedBox(height: 1),
      ],
    );
  }

  Component _buildTotalRow({
    required TuiThemeData theme,
    required String totalProgressText,
    required double? totalPercent,
  }) {
    return Column(
      children: [
        const Divider(),
        Text(
          'Total',
          style: TextStyle(
            color: theme.primary,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        Row(
          children: [
            Expanded(
              child: ProgressBar(
                value: totalPercent,
                indeterminate: totalPercent == null,
                borderStyle: ProgressBarBorderStyle.single,
                valueColor: theme.success,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              totalProgressText,
              style: TextStyle(
                color: theme.onSurface,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatProgressSummary(int received, int? total) {
    final receivedLabel = _formatBytes(received);
    if (total == null || total <= 0) {
      return receivedLabel;
    }
    final totalLabel = _formatBytes(total);
    final percent = (received / total * 100).clamp(0, 100).toStringAsFixed(1);
    return '$receivedLabel / $totalLabel ($percent%)';
  }

  String _formatTotalProgressText(int received, int? total) {
    if (received == 0 && (total == null || total <= 0)) {
      return '--';
    }
    return _formatProgressSummary(received, total);
  }

  String _formatSpeed(double? bytesPerSecond) {
    if (bytesPerSecond == null || bytesPerSecond <= 0) {
      return '--';
    }
    return '${_formatBytes(bytesPerSecond.round())}/s';
  }

  String _downloadStatusLine(String filesText, String speedText) {
    if (filesText.isEmpty) {
      return 'Downloading models...  $speedText';
    }
    return 'Downloading models...  $filesText  $speedText';
  }

  String _formatBytes(int bytes) {
    const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    return '${value.toStringAsFixed(1)} ${units[unitIndex]}';
  }

  double _clamp01(double value) {
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  int _sumReceivedBytes(List<StartupFileState> files) {
    var total = 0;
    for (final file in files) {
      total += file.receivedBytes;
    }
    return total;
  }

  int? _totalBytesOrNull(List<StartupFileState> files) {
    if (files.isEmpty) {
      return null;
    }
    var total = 0;
    for (final file in files) {
      final fileTotal = file.totalBytes;
      if (fileTotal == null || fileTotal <= 0) {
        return null;
      }
      total += fileTotal;
    }
    return total;
  }

  List<Component> _buildFileRows(
    List<StartupFileState> files,
    TuiThemeData theme,
  ) {
    if (files.isEmpty) {
      return const <Component>[];
    }
    final rows = <Component>[];
    for (var i = 0; i < files.length; i += 1) {
      final file = files[i];
      final label = file.label;
      final style = _fileRowStyle(file, theme);

      rows
        ..add(
          Text(
            label,
            style: TextStyle(color: style.labelColor),
          ),
        )
        ..add(
          Row(
            children: [
              Expanded(
                child: ProgressBar(
                  value: style.percent,
                  indeterminate: style.indeterminate,
                  borderStyle: ProgressBarBorderStyle.single,
                  valueColor: style.barColor,
                ),
              ),
              const SizedBox(width: 1),
              Text(
                style.progressText,
                style: TextStyle(
                  color: theme.onSurface,
                ),
              ),
            ],
          ),
        );
      if (i < files.length - 1) {
        rows.add(const Divider());
      }
    }
    return rows;
  }

  _FileRowStyle _fileRowStyle(
    StartupFileState file,
    TuiThemeData theme,
  ) {
    final isDownloading = file.status == StartupFileStatus.downloading;
    final isCompleted =
        file.status == StartupFileStatus.completed ||
        file.status == StartupFileStatus.skipped;
    final labelColor = isDownloading
        ? theme.primary
        : isCompleted
        ? theme.success
        : theme.secondary;
    final barColor = isDownloading
        ? theme.primary
        : isCompleted
        ? theme.success
        : theme.outline;
    final progressText = switch (file.status) {
      StartupFileStatus.downloading => _formatProgressSummary(
        file.receivedBytes,
        file.totalBytes,
      ),
      StartupFileStatus.completed => 'Done',
      StartupFileStatus.skipped => 'Installed',
      StartupFileStatus.queued => 'Queued',
    };
    final percent = switch (file.status) {
      StartupFileStatus.downloading => switch (file.totalBytes ?? 0) {
        <= 0 => null,
        _ => _clamp01(file.receivedBytes / file.totalBytes!),
      },
      StartupFileStatus.completed => 1.0,
      StartupFileStatus.skipped => 1.0,
      StartupFileStatus.queued => 0.0,
    };
    final indeterminate =
        file.status == StartupFileStatus.downloading && file.totalBytes == null;

    return _FileRowStyle(
      labelColor: labelColor,
      barColor: barColor,
      progressText: progressText,
      percent: percent,
      indeterminate: indeterminate,
    );
  }
}

final class _FileRowStyle {
  const _FileRowStyle({
    required this.labelColor,
    required this.barColor,
    required this.progressText,
    required this.percent,
    required this.indeterminate,
  });

  final Color labelColor;
  final Color barColor;
  final String progressText;
  final double? percent;
  final bool indeterminate;
}
