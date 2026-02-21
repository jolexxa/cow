import 'package:cow/src/features/startup/state/startup_data.dart';
import 'package:cow/src/features/startup/state/startup_input.dart';
import 'package:cow/src/features/startup/state/startup_output.dart';
import 'package:cow_model_manager/cow_model_manager.dart';
import 'package:logic_blocks/logic_blocks.dart';

sealed class StartupState extends StateLogic<StartupState> {
  StartupData get data => get<StartupData>();

  Map<String, StartupFileState> get files => data.files;
  int get totalFiles => data.totalFiles;
  int get completedFiles => data.completedFiles;
  ModelInstallProgress? get progress => data.progress;
  String? get error => data.error;
}

final class UninitializedState extends StartupState {
  UninitializedState() {
    on<Start>((_) {
      output(const CheckFilesRequested());
      return to<CheckingState>();
    });
  }
}

final class CheckingState extends StartupState {
  CheckingState() {
    on<FileCheckComplete>((input) {
      data.files = input.files;

      if (data.completedFiles == data.totalFiles && data.totalFiles > 0) {
        return to<ReadyState>();
      }

      output(const StartDownloadRequested());
      return to<DownloadingState>();
    });

    on<Cancel>((_) {
      output(const CancelDownloadRequested());
      data.error = 'Startup cancelled.';
      return to<ErrorState>();
    });
  }
}

final class DownloadingState extends StartupState {
  DownloadingState() {
    on<DownloadProgress>((input) {
      final progress = input.progress;
      final label = '${progress.profile.id}/${progress.file.fileName}';

      if (!progress.fileSkipped) {
        data.downloadedAny = true;
      }

      final previous = data.files[label];
      if (previous != null) {
        final status = progress.fileCompleted
            ? (progress.fileSkipped
                  ? StartupFileStatus.skipped
                  : StartupFileStatus.completed)
            : StartupFileStatus.downloading;

        data.files[label] = previous.copyWith(
          status: status,
          receivedBytes: progress.fileReceivedBytes,
          totalBytes: progress.fileTotalBytes ?? previous.totalBytes,
        );
      }

      data.progress = progress;
      output(const StateUpdated());
      return toSelf();
    });

    on<DownloadComplete>((_) {
      if (data.downloadedAny) {
        return to<AwaitingInputState>();
      }
      return to<ReadyState>();
    });

    on<DownloadCancelled>((_) {
      data.error = 'Download cancelled. Restart Cow to try again.';
      return to<ErrorState>();
    });

    on<DownloadFailed>((input) {
      data.error = input.error;
      return to<ErrorState>();
    });

    on<Cancel>((_) {
      output(const CancelDownloadRequested());
      return toSelf();
    });
  }
}

final class AwaitingInputState extends StartupState {
  AwaitingInputState() {
    on<Continue>((_) {
      return to<ReadyState>();
    });
  }
}

final class ReadyState extends StartupState {}

final class ErrorState extends StartupState {}

final class StartupLogic extends LogicBlock<StartupState> {
  StartupLogic() {
    set(StartupData());
    set(UninitializedState());
    set(CheckingState());
    set(DownloadingState());
    set(AwaitingInputState());
    set(ReadyState());
    set(ErrorState());
  }

  @override
  Transition getInitialState() => to<UninitializedState>();
}
