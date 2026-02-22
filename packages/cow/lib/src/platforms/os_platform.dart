import 'dart:ffi';
import 'dart:io';

import 'package:cow/src/app/app_model_profile.dart';
import 'package:cow/src/app/app_model_profiles.dart';
import 'package:cow/src/app/cow_paths.dart';
import 'package:cow_brain/cow_brain.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:mlx_dart/mlx_dart.dart';
import 'package:nocterm/nocterm.dart';
import 'package:path/path.dart' as p;

part 'linux.dart';
part 'macos.dart';

sealed class OSPlatform {
  const OSPlatform();

  factory OSPlatform.current() {
    if (Platform.isMacOS) {
      return MacOS();
    }
    if (Platform.isLinux) {
      return const Linux();
    }

    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  int get nGpuLayers;

  int defaultThreadCount() {
    final cores = Platform.numberOfProcessors;
    if (cores <= 4) {
      return cores - 1;
    }
    return cores - 2;
  }

  /// Shuts down the terminal and exits the process with the given [code].
  void exit([int code = 0]) {
    TerminalBinding.instance.requestShutdown(code);
  }

  bool get useFlashAttn;

  int get openFlagWriteOnly;
  int get openFlagCreate;
  int get openFlagAppend;
  int get openFlagTrunc;

  /// Resolves the llama library path.
  ///
  /// Uses [LlamaCpp.resolveLibraryPath] with a fallback to the dev assets
  /// directory when running via `dart run` (where [Platform.resolvedExecutable]
  /// points to the Dart SDK rather than the script).
  String resolveLlamaLibraryPath() {
    // For compiled binaries, Platform.resolvedExecutable is the app itself,
    // so ../lib/ contains the bundled native libraries.
    final executableDir = File(Platform.resolvedExecutable).parent;
    final bundledPath = LlamaCpp.resolveLibraryPath(
      executableDir: executableDir,
    );
    if (File(bundledPath).existsSync()) {
      return bundledPath;
    }

    // During `dart run`, fall back to dev assets relative to the script.
    return _devAssetPath();
  }

  String _devAssetPath();

  /// Default primary model ID for this platform.
  AppModelId get defaultPrimaryModelId;

  /// Default lightweight (summary) model ID for this platform.
  AppModelId get defaultLightweightModelId;

  static const int defaultContextSize = 10000;
  static const int batchSize = 512;

  /// Build backend-specific runtime options for the given [profile].
  BackendRuntimeOptions buildRuntimeOptions({
    required AppModelProfile profile,
    required CowPaths cowPaths,
    required int seed,
    int? maxOutputTokensOverride,
  });

  /// Build [SamplingOptions] from a model's runtime config.
  SamplingOptions buildSampling(AppModelProfile profile, int seed) {
    final config = profile.runtimeConfig;
    return SamplingOptions(
      seed: seed,
      temperature: config.temperature,
      topK: config.topK,
      topP: config.topP,
      minP: config.minP,
      penaltyRepeat: config.penaltyRepeat,
      penaltyLastN: config.penaltyLastN,
    );
  }

  /// Build [LlamaCppRuntimeOptions] — shared across all platforms.
  LlamaCppRuntimeOptions buildLlamaCppOptions({
    required AppModelProfile profile,
    required CowPaths cowPaths,
    required SamplingOptions sampling,
    required int contextSize,
    required int maxOutputTokens,
    required int nGpuLayers,
  }) {
    return LlamaCppRuntimeOptions(
      modelPath: cowPaths.modelEntrypoint(profile.downloadableModel),
      libraryPath: resolveLlamaLibraryPath(),
      modelOptions: LlamaModelOptions(
        nGpuLayers: nGpuLayers,
        useMmap: true,
        useMlock: true,
      ),
      maxOutputTokensDefault: maxOutputTokens,
      samplingOptions: sampling,
      contextOptions: LlamaContextOptions(
        contextSize: contextSize,
        nBatch: batchSize,
        nThreads: defaultThreadCount(),
        nThreadsBatch: defaultThreadCount(),
        useFlashAttn: useFlashAttn,
      ),
    );
  }
}
