import 'package:cow/src/features/startup/state/startup_data.dart';
import 'package:cow_model_manager/cow_model_manager.dart';

sealed class StartupInput {
  const StartupInput();
}

final class Start extends StartupInput {
  const Start();
}

final class FileCheckComplete extends StartupInput {
  const FileCheckComplete(this.files);

  final Map<String, StartupFileState> files;
}

final class DownloadProgress extends StartupInput {
  const DownloadProgress(this.progress);

  final ModelInstallProgress progress;
}

final class DownloadComplete extends StartupInput {
  const DownloadComplete();
}

final class DownloadCancelled extends StartupInput {
  const DownloadCancelled();
}

final class DownloadFailed extends StartupInput {
  const DownloadFailed(this.error);

  final String error;
}

final class Cancel extends StartupInput {
  const Cancel();
}

final class Continue extends StartupInput {
  const Continue();
}
