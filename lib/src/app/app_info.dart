import 'dart:math';

import 'package:blocterm/blocterm.dart';
import 'package:cow/src/app/app_model_profiles.dart';
import 'package:cow/src/platforms/platform.dart';
import 'package:cow_brain/cow_brain.dart';
import 'package:cow_model_manager/cow_model_manager.dart';
import 'package:nocterm/nocterm.dart';

abstract class AppInfo {
  const AppInfo();

  static const String executableName = 'cow';
  static const String packageName = 'cow';
  static const String description = 'An humble AI in your terminal.';

  static const int batchSize = 512;

  static const int contextSize = 10_000;
  static const int maxTokens = contextSize ~/ 2;

  static const int summaryContextSize = 2048;
  static const int summaryMaxTokens = 512;

  static Future<AppInfo> initialize({
    required OSPlatform platform,
  }) async {
    final modelProfile = AppModelProfiles.primaryProfile;
    final summaryModelProfile = AppModelProfiles.lightweightProfile;
    final cowPaths = CowPaths();
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

    final libraryPath = platform.resolveLlamaLibraryPath();
    final modelPath = cowPaths.modelEntrypoint(modelProfile);
    final requiredProfilesPresent =
        profileFilesPresent(modelProfile, cowPaths) &&
        profileFilesPresent(summaryModelProfile, cowPaths);

    final rng = Random();
    final runtimeOptions = LlamaRuntimeOptions(
      modelPath: modelPath,
      libraryPath: libraryPath,
      modelOptions: LlamaModelOptions(
        nGpuLayers: platform.nGpuLayers,
        useMmap: true,
        useMlock: false,
      ),
      maxOutputTokensDefault: maxTokens,
      samplingOptions: LlamaSamplingOptions(seed: rng.nextInt(1 << 31)),
      contextOptions: LlamaContextOptions(
        contextSize: contextSize,
        nBatch: batchSize,
        nThreads: platform.defaultThreadCount(),
        nThreadsBatch: platform.defaultThreadCount(),
        useFlashAttn: platform.useFlashAttn,
      ),
    );

    final summaryModelPath = cowPaths.modelEntrypoint(
      summaryModelProfile,
    );
    final summaryRuntimeOptions = LlamaRuntimeOptions(
      modelPath: summaryModelPath,
      libraryPath: libraryPath,
      modelOptions: const LlamaModelOptions(
        nGpuLayers: 0, // Run summary on CPU
        useMmap: true,
        useMlock: false,
      ),
      samplingOptions: LlamaSamplingOptions(
        seed: rng.nextInt(1 << 31),
        temperature: 0.3,
      ),
      contextOptions: LlamaContextOptions(
        contextSize: summaryContextSize,
        nBatch: batchSize,
        nThreads: platform.defaultThreadCount(),
        nThreadsBatch: platform.defaultThreadCount(),
        useFlashAttn: platform.useFlashAttn,
      ),
    );

    return AppInfoProduction(
      platform: platform,
      toolRegistry: toolRegistry,
      modelProfile: modelProfile,
      summaryModelProfile: summaryModelProfile,
      llamaRuntimeOptions: runtimeOptions,
      summaryRuntimeOptions: summaryRuntimeOptions,
      requiredProfilesPresent: requiredProfilesPresent,
      cowPaths: cowPaths,
    );
  }

  static AppInfo of(BuildContext context) => Provider.of<AppInfo>(context);

  ToolRegistry get toolRegistry;
  OSPlatform get platform;
  ModelProfileSpec get modelProfile;
  ModelProfileSpec get summaryModelProfile;
  LlamaRuntimeOptions get llamaRuntimeOptions;
  LlamaRuntimeOptions get summaryRuntimeOptions;
  bool get requiredProfilesPresent;
  CowPaths get cowPaths;
}

class AppInfoProduction extends AppInfo {
  const AppInfoProduction({
    required this.toolRegistry,
    required this.platform,
    required this.modelProfile,
    required this.summaryModelProfile,
    required this.llamaRuntimeOptions,
    required this.summaryRuntimeOptions,
    required this.requiredProfilesPresent,
    required this.cowPaths,
  });

  @override
  final ToolRegistry toolRegistry;
  @override
  final OSPlatform platform;
  @override
  final ModelProfileSpec modelProfile;
  @override
  final ModelProfileSpec summaryModelProfile;
  @override
  final LlamaRuntimeOptions llamaRuntimeOptions;
  @override
  final LlamaRuntimeOptions summaryRuntimeOptions;
  @override
  final bool requiredProfilesPresent;
  @override
  final CowPaths cowPaths;
}
