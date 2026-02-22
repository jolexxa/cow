import 'package:cow/src/app/app_model_profile.dart';
import 'package:cow/src/app/app_model_profiles.dart';
import 'package:cow/src/app/cow_config.dart';
import 'package:cow/src/app/model_runtime_config.dart';
import 'package:cow/src/platforms/platform.dart';
import 'package:cow_brain/cow_brain.dart';
import 'package:cow_model_manager/cow_model_manager.dart';

class ResolvedModels {
  const ResolvedModels({
    required this.primary,
    required this.lightweight,
  });

  final AppModelProfile primary;
  final AppModelProfile lightweight;
}

class ConfigResolver {
  /// Merges user config with built-in defaults.
  ///
  /// Uses [platform] to determine the default primary and lightweight models
  /// (e.g. MLX variants on Apple Silicon, llama.cpp elsewhere).
  static ResolvedModels resolve(
    CowConfig config, {
    required OSPlatform platform,
  }) {
    final builtins = AppModelProfiles.builtins;
    final resolved = <String, AppModelProfile>{...builtins};

    for (final entry in config.models.entries) {
      final id = entry.key;
      final userModel = entry.value;

      if (builtins.containsKey(id)) {
        resolved[id] = _mergeOverride(builtins[id]!, userModel);
      } else {
        resolved[id] = _buildCustom(id, userModel);
      }
    }

    final primaryId = config.primaryModel ?? platform.defaultPrimaryModelId;
    final lightId =
        config.lightweightModel ?? platform.defaultLightweightModelId;

    final primary = resolved[primaryId];
    final lightweight = resolved[lightId];

    if (primary == null) {
      throw Exception('Primary model "$primaryId" not found.');
    }
    if (lightweight == null) {
      throw Exception('Lightweight model "$lightId" not found.');
    }

    return ResolvedModels(primary: primary, lightweight: lightweight);
  }

  static AppModelProfile _mergeOverride(
    AppModelProfile builtin,
    CowModelConfig userModel,
  ) {
    return AppModelProfile(
      downloadableModel: builtin.downloadableModel,
      modelFamily: userModel.modelFamily != null
          ? _parseModelFamily(userModel.modelFamily!)
          : builtin.modelFamily,
      backend: userModel.backend != null
          ? _parseBackend(userModel.backend!)
          : builtin.backend,
      supportsReasoning:
          userModel.supportsReasoning ?? builtin.supportsReasoning,
      runtimeConfig: builtin.runtimeConfig.mergeWith(userModel.runtimeConfig),
    );
  }

  static AppModelProfile _buildCustom(String id, CowModelConfig userModel) {
    if (userModel.files == null || userModel.files!.isEmpty) {
      throw Exception(
        'Custom model "$id" must have at least one file.',
      );
    }
    if (userModel.entrypointFileName == null) {
      throw Exception(
        'Custom model "$id" must specify "entrypointFileName".',
      );
    }
    if (userModel.backend == null) {
      throw Exception(
        'Custom model "$id" must specify "backend" ("llama_cpp" or "mlx").',
      );
    }

    final files = userModel.files!
        .map(
          (f) => DownloadableModelFile(url: f.url, fileName: f.fileName),
        )
        .toList();

    return AppModelProfile(
      downloadableModel: DownloadableModel(
        id: id,
        files: files,
        entrypointFileName: userModel.entrypointFileName!,
      ),
      modelFamily: userModel.modelFamily != null
          ? _parseModelFamily(userModel.modelFamily!)
          : ModelProfileId.auto,
      backend: _parseBackend(userModel.backend!),
      supportsReasoning: userModel.supportsReasoning ?? false,
      runtimeConfig: userModel.runtimeConfig ?? const ModelRuntimeConfig(),
    );
  }

  static ModelProfileId _parseModelFamily(String value) {
    return switch (value) {
      'qwen3' => ModelProfileId.qwen3,
      'qwen25' => ModelProfileId.qwen25,
      'auto' => ModelProfileId.auto,
      _ => throw Exception(
        'Unknown modelFamily "$value". '
        'Expected one of: qwen3, qwen25, auto.',
      ),
    };
  }

  static InferenceBackend _parseBackend(String value) {
    return switch (value) {
      'llama_cpp' => InferenceBackend.llamaCpp,
      'mlx' => InferenceBackend.mlx,
      _ => throw Exception(
        'Unknown backend "$value". '
        'Expected one of: llama_cpp, mlx.',
      ),
    };
  }
}
