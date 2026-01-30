import 'package:cow_model_manager/cow_model_manager.dart';
import 'package:meta/meta.dart';

enum StartupStatus {
  checking,
  downloading,
  awaitingInput,
  ready,
  error,
}

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

@immutable
class StartupState {
  const StartupState({
    required this.status,
    required this.completedFiles,
    required this.totalFiles,
    required this.files,
    this.progress,
    this.error,
  });

  factory StartupState.checking() {
    return const StartupState(
      status: StartupStatus.checking,
      completedFiles: 0,
      totalFiles: 0,
      files: <StartupFileState>[],
    );
  }

  StartupState copyWith({
    StartupStatus? status,
    ModelInstallProgress? progress,
    String? error,
    int? completedFiles,
    int? totalFiles,
    List<StartupFileState>? files,
  }) {
    return StartupState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error,
      completedFiles: completedFiles ?? this.completedFiles,
      totalFiles: totalFiles ?? this.totalFiles,
      files: files ?? this.files,
    );
  }

  final StartupStatus status;
  final ModelInstallProgress? progress;
  final String? error;
  final int completedFiles;
  final int totalFiles;
  final List<StartupFileState> files;
}
