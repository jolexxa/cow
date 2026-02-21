import 'dart:async';
import 'dart:io';

import 'package:cow/src/app/cow_paths.dart';
import 'package:cow/src/app/logic_bloc.dart';
import 'package:cow/src/features/startup/state/startup_data.dart';
import 'package:cow/src/features/startup/state/startup_input.dart';
import 'package:cow/src/features/startup/state/startup_logic.dart';
import 'package:cow/src/features/startup/state/startup_output.dart';
import 'package:cow_model_manager/cow_model_manager.dart';

class StartupCubit extends LogicBloc<StartupState> {
  StartupCubit({
    required List<DownloadableModel> installProfiles,
    required CowPaths cowPaths,
    required StartupLogic logic,
    ModelInstaller? installer,
  }) : _installProfiles = installProfiles,
       _cowPaths = cowPaths,
       _installer = installer ?? ModelInstaller(modelsDir: cowPaths.modelsDir),
       _controller = ModelInstallController(),
       super(logic) {
    _setupBindings();
  }

  final List<DownloadableModel> _installProfiles;
  final CowPaths _cowPaths;
  final ModelInstaller _installer;
  final ModelInstallController _controller;

  bool _disposed = false;

  void _setupBindings() {
    binding
      ..onOutput<StateUpdated>((_) => emit(state))
      ..onOutput<CheckFilesRequested>((_) => _checkFiles())
      ..onOutput<StartDownloadRequested>((_) => unawaited(_startDownload()))
      ..onOutput<CancelDownloadRequested>((_) => _cancelDownload());
  }

  void start() => input(const Start());

  void cancel() => input(const Cancel());

  void continueStartup() => input(const Continue());

  @override
  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    _controller.cancel();
    return super.close();
  }

  void _checkFiles() {
    final fileStates = <String, StartupFileState>{};

    for (final profile in _installProfiles) {
      for (final file in profile.files) {
        final label = '${profile.id}/${file.fileName}';
        final path = _cowPaths.modelFilePath(profile, file);

        if (File(path).existsSync()) {
          final size = File(path).lengthSync();
          fileStates[label] = StartupFileState(
            label: label,
            status: StartupFileStatus.skipped,
            receivedBytes: size,
            totalBytes: size,
          );
        } else {
          fileStates[label] = StartupFileState(
            label: label,
            status: StartupFileStatus.queued,
            receivedBytes: 0,
            totalBytes: null,
          );
        }
      }
    }

    input(FileCheckComplete(fileStates));
  }

  Future<void> _startDownload() async {
    try {
      await for (final progress in _installer.ensureInstalled(
        _installProfiles,
        controller: _controller,
      )) {
        input(DownloadProgress(progress));
      }
      input(const DownloadComplete());
    } on ModelInstallCancelled {
      input(const DownloadCancelled());
    } on Exception catch (error) {
      input(DownloadFailed(error.toString()));
    }
  }

  void _cancelDownload() {
    _controller.cancel();
  }
}
