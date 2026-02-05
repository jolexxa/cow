import 'package:cow_model_manager/src/downloadable_model.dart';

class ModelInstallController {
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

class ModelInstallCancelled implements Exception {
  const ModelInstallCancelled();

  @override
  String toString() => 'Model installation cancelled.';
}

class ModelInstallProgress {
  ModelInstallProgress({
    required this.profile,
    required this.file,
    required this.fileReceivedBytes,
    required this.fileTotalBytes,
    required this.totalReceivedBytes,
    required this.totalBytes,
    required this.speedBytesPerSecond,
    required this.fileCompleted,
    required this.fileSkipped,
  });

  final DownloadableModel profile;
  final DownloadableModelFile file;
  final int fileReceivedBytes;
  final int? fileTotalBytes;
  final int totalReceivedBytes;
  final int? totalBytes;
  final double? speedBytesPerSecond;
  final bool fileCompleted;
  final bool fileSkipped;
}
