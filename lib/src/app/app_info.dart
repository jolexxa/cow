import 'dart:math';

import 'package:blocterm/blocterm.dart';
import 'package:cow/src/app/app_model_profile.dart';
import 'package:cow/src/app/config_resolver.dart';
import 'package:cow/src/app/cow_config.dart';
import 'package:cow/src/app/cow_paths.dart';
import 'package:cow/src/platforms/platform.dart';
import 'package:cow_brain/cow_brain.dart';
import 'package:cow_model_manager/cow_model_manager.dart';
import 'package:nocterm/nocterm.dart';

class AppInfo {
  const AppInfo({
    required this.platform,
    required this.toolRegistry,
    required this.modelProfile,
    required this.summaryModelProfile,
    required this.primaryOptions,
    required this.summaryOptions,
    required this.requiredProfilesPresent,
    required this.cowPaths,
    required this.modelServer,
  });

  static const String executableName = 'cow';
  static const String packageName = 'cow';
  static const String description = 'An humble AI in your terminal.';

  static const int _batchSize = 512;
  static const int _defaultContextSize = 10000;
  static const int _summaryMaxTokens = 512;

  final ToolRegistry toolRegistry;
  final OSPlatform platform;
  final AppModelProfile modelProfile;
  final AppModelProfile summaryModelProfile;
  final BackendRuntimeOptions primaryOptions;
  final BackendRuntimeOptions summaryOptions;
  final bool requiredProfilesPresent;
  final CowPaths cowPaths;
  final ModelServer modelServer;

  static Future<AppInfo> initialize({
    required OSPlatform platform,
  }) async {
    final cowPaths = CowPaths();
    final config = CowConfig.fromFile(cowPaths.configFile);
    final mlxAvailable = platform.resolveMlxLibraryPath() != null;
    final resolved = ConfigResolver.resolve(config, mlxAvailable: mlxAvailable);
    final modelProfile = resolved.primary;
    final summaryModelProfile = resolved.lightweight;
    final toolRegistry = ToolRegistry()
      ..register(
        const ToolDefinition(
          name: 'date_time',
          description: 'Returns the current date/time in ISO 8601 format.',
          parameters: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
            'required': <String>[],
          },
        ),
        (_) => DateTime.now().toIso8601String(),
      );

    final modelsDir = cowPaths.modelsDir;
    final requiredProfilesPresent =
        profileFilesPresent(modelProfile.downloadableModel, modelsDir) &&
        profileFilesPresent(
          summaryModelProfile.downloadableModel,
          modelsDir,
        );

    final rng = Random();
    final mlxLibraryPath = platform.resolveMlxLibraryPath();

    final primaryOptions = _buildOptions(
      profile: modelProfile,
      platform: platform,
      cowPaths: cowPaths,
      seed: rng.nextInt(1 << 31),
      nGpuLayers: platform.nGpuLayers,
      mlxLibraryPath: mlxLibraryPath,
    );

    final summaryOptions = _buildOptions(
      profile: summaryModelProfile,
      platform: platform,
      cowPaths: cowPaths,
      seed: rng.nextInt(1 << 31),
      nGpuLayers: 0, // Run summary on CPU
      mlxLibraryPath: mlxLibraryPath,
      maxOutputTokensOverride: _summaryMaxTokens,
    );

    final modelServer = await ModelServer.spawn();

    return AppInfo(
      platform: platform,
      toolRegistry: toolRegistry,
      modelProfile: modelProfile,
      summaryModelProfile: summaryModelProfile,
      primaryOptions: primaryOptions,
      summaryOptions: summaryOptions,
      requiredProfilesPresent: requiredProfilesPresent,
      cowPaths: cowPaths,
      modelServer: modelServer,
    );
  }

  static BackendRuntimeOptions _buildOptions({
    required AppModelProfile profile,
    required OSPlatform platform,
    required CowPaths cowPaths,
    required int seed,
    required int nGpuLayers,
    required String? mlxLibraryPath,
    int? maxOutputTokensOverride,
  }) {
    final config = profile.runtimeConfig;
    final contextSize = config.contextSize ?? _defaultContextSize;
    final maxOut = maxOutputTokensOverride ?? (contextSize ~/ 2);

    final sampling = SamplingOptions(
      seed: seed,
      temperature: config.temperature,
      topK: config.topK,
      topP: config.topP,
      minP: config.minP,
      penaltyRepeat: config.penaltyRepeat,
      penaltyLastN: config.penaltyLastN,
    );

    if (profile.backend == InferenceBackend.mlx && mlxLibraryPath != null) {
      return MlxRuntimeOptions(
        modelPath: cowPaths.modelDir(profile.downloadableModel),
        libraryPath: mlxLibraryPath,
        contextSize: contextSize,
        maxOutputTokensDefault: maxOut,
        samplingOptions: sampling,
      );
    }

    return LlamaCppRuntimeOptions(
      modelPath: cowPaths.modelEntrypoint(profile.downloadableModel),
      libraryPath: platform.resolveLlamaLibraryPath(),
      modelOptions: LlamaModelOptions(
        nGpuLayers: nGpuLayers,
        useMmap: true,
        useMlock: false,
      ),
      maxOutputTokensDefault: maxOut,
      samplingOptions: sampling,
      contextOptions: LlamaContextOptions(
        contextSize: contextSize,
        nBatch: _batchSize,
        nThreads: platform.defaultThreadCount(),
        nThreadsBatch: platform.defaultThreadCount(),
        useFlashAttn: platform.useFlashAttn,
      ),
    );
  }

  static AppInfo of(BuildContext context) => Provider.of<AppInfo>(context);
}
