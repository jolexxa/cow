import 'package:cow_model_manager/cow_model_manager.dart';
import 'package:meta/meta.dart';

enum StartupFileStatus {
  queued,
  downloading,
  completed,
  skipped,
}

@immutable
class StartupFileState {
  const StartupFileState({
    required this.label,
    required this.status,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final String label;
  final StartupFileStatus status;
  final int receivedBytes;
  final int? totalBytes;

  StartupFileState copyWith({
    StartupFileStatus? status,
    int? receivedBytes,
    int? totalBytes,
  }) {
    return StartupFileState(
      label: label,
      status: status ?? this.status,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
    );
  }
}

final class StartupData {
  Map<String, StartupFileState> files = {};
  ModelInstallProgress? progress;
  bool downloadedAny = false;
  String? error;

  int get totalFiles => files.length;
  int get completedFiles => files.values
      .where(
        (f) =>
            f.status == StartupFileStatus.completed ||
            f.status == StartupFileStatus.skipped,
      )
      .length;
}
