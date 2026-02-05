import 'package:cow/src/app/app_model_profile.dart';
import 'package:cow/src/app/app_model_profiles.dart';
import 'package:cow/src/app/cow_config.dart';
import 'package:cow/src/app/model_runtime_config.dart';
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
  static ResolvedModels resolve(CowConfig config) {
    final builtins = <String, AppModelProfile>{
      AppModelId.qwen3.name: AppModelProfiles.qwen3,
      AppModelId.qwen25.name: AppModelProfiles.qwen25,
      AppModelId.qwen25_3b.name: AppModelProfiles.qwen25_3b,
    };

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

    final primaryId = config.primaryModel ?? AppModelId.qwen3.name;
    final lightId = config.lightweightModel ?? AppModelId.qwen25_3b.name;

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
          : LlamaProfileId.auto,
      supportsReasoning: userModel.supportsReasoning ?? false,
      runtimeConfig: userModel.runtimeConfig ?? const ModelRuntimeConfig(),
    );
  }

  static LlamaProfileId _parseModelFamily(String value) {
    return switch (value) {
      'qwen3' => LlamaProfileId.qwen3,
      'qwen25' => LlamaProfileId.qwen25,
      'auto' => LlamaProfileId.auto,
      _ => throw Exception(
        'Unknown modelFamily "$value". '
        'Expected one of: qwen3, qwen25, auto.',
      ),
    };
  }
}
