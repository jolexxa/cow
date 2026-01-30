import 'dart:async';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:cow/src/features/startup/startup_bloc/startup_event.dart';
import 'package:cow/src/features/startup/startup_bloc/startup_state.dart';
import 'package:cow_model_manager/cow_model_manager.dart';

class StartupBloc extends Bloc<StartupEvent, StartupState> {
  StartupBloc({
    required List<ModelProfileSpec> installProfiles,
    required CowPaths cowPaths,
    ModelInstaller? installer,
  }) : _installProfiles = installProfiles,
       _cowPaths = cowPaths,
       _installer = installer ?? ModelInstaller(paths: cowPaths),
       _controller = ModelInstallController(),
       super(StartupState.checking()) {
    on<AppStartupStarted>(_onStarted);
    on<AppStartupCancelled>(_onCancelled);
    on<AppStartupContinue>(_onContinue);
  }

  final List<ModelProfileSpec> _installProfiles;
  final CowPaths _cowPaths;
  final ModelInstaller _installer;
  final ModelInstallController _controller;

  Future<void> _onStarted(
    AppStartupStarted event,
    Emitter<StartupState> emit,
  ) async {
    final specs = _installProfiles;
    final fileEntries =
        <
          ({
            String label,
            ModelProfileSpec profile,
            ModelFileSpec file,
          })
        >[];
    for (final profile in specs) {
      for (final file in profile.files) {
        fileEntries.add((
          label: '${profile.id}/${file.fileName}',
          profile: profile,
          file: file,
        ));
      }
    }
    final totalFiles = fileEntries.length;
    final fileStates = <StartupFileState>[];
    var completedFiles = 0;
    for (final entry in fileEntries) {
      final path = _cowPaths.modelFilePath(entry.profile, entry.file);
      if (File(path).existsSync()) {
        final size = File(path).lengthSync();
        fileStates.add(
          StartupFileState(
            label: entry.label,
            status: StartupFileStatus.skipped,
            receivedBytes: size,
            totalBytes: size,
          ),
        );
        completedFiles += 1;
      } else {
        fileStates.add(
          StartupFileState(
            label: entry.label,
            status: StartupFileStatus.queued,
            receivedBytes: 0,
            totalBytes: null,
          ),
        );
      }
    }

    emit(
      state.copyWith(
        status: StartupStatus.checking,
        totalFiles: totalFiles,
        completedFiles: completedFiles,
        files: List<StartupFileState>.unmodifiable(fileStates),
      ),
    );

    if (completedFiles == totalFiles && totalFiles > 0) {
      emit(
        state.copyWith(
          status: StartupStatus.ready,
          files: List<StartupFileState>.unmodifiable(fileStates),
          completedFiles: completedFiles,
        ),
      );
      return;
    }

    var downloadedAny = false;
    final labelIndex = <String, int>{};
    for (var i = 0; i < fileStates.length; i += 1) {
      labelIndex[fileStates[i].label] = i;
    }
    var runningStates = List<StartupFileState>.from(fileStates);
    String? currentLabel;

    try {
      await for (final progress in _installer.ensureInstalled(
        specs,
        controller: _controller,
      )) {
        currentLabel = '${progress.profile.id}/${progress.file.fileName}';
        if (!progress.fileSkipped) {
          downloadedAny = true;
        }
        final index = labelIndex[currentLabel];
        if (index != null) {
          final status = progress.fileCompleted
              ? (progress.fileSkipped
                    ? StartupFileStatus.skipped
                    : StartupFileStatus.completed)
              : StartupFileStatus.downloading;
          final previous = runningStates[index];
          final totalBytes = progress.fileTotalBytes ?? previous.totalBytes;
          runningStates = List<StartupFileState>.from(runningStates);
          runningStates[index] = previous.copyWith(
            status: status,
            receivedBytes: progress.fileReceivedBytes,
            totalBytes: totalBytes,
          );
        }
        completedFiles = runningStates
            .where(
              (file) =>
                  file.status == StartupFileStatus.completed ||
                  file.status == StartupFileStatus.skipped,
            )
            .length;
        emit(
          state.copyWith(
            status: StartupStatus.downloading,
            progress: progress,
            completedFiles: completedFiles,
            totalFiles: totalFiles,
            files: List<StartupFileState>.unmodifiable(runningStates),
          ),
        );
      }

      emit(
        state.copyWith(
          status: downloadedAny
              ? StartupStatus.awaitingInput
              : StartupStatus.ready,
          files: List<StartupFileState>.unmodifiable(runningStates),
        ),
      );
    } on ModelInstallCancelled {
      emit(
        state.copyWith(
          status: StartupStatus.error,
          error: 'Download cancelled. Restart Cow to try again.',
          files: List<StartupFileState>.unmodifiable(runningStates),
        ),
      );
    } on Exception catch (error) {
      emit(
        state.copyWith(
          status: StartupStatus.error,
          error: error.toString(),
          files: List<StartupFileState>.unmodifiable(runningStates),
        ),
      );
    }
  }

  void _onCancelled(
    AppStartupCancelled event,
    Emitter<StartupState> emit,
  ) {
    _controller.cancel();
  }

  void _onContinue(
    AppStartupContinue event,
    Emitter<StartupState> emit,
  ) {
    emit(
      state.copyWith(
        status: StartupStatus.ready,
      ),
    );
  }
}
