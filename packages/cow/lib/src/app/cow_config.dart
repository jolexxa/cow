import 'dart:convert';
import 'dart:io';

import 'package:cow/src/app/model_runtime_config.dart';
import 'package:json_annotation/json_annotation.dart';

part 'cow_config.g.dart';

/// Raw deserialized config from ~/.cow/cow.json.
@JsonSerializable(explicitToJson: true)
class CowConfig {
  const CowConfig({
    this.models = const {},
    this.primaryModel,
    this.lightweightModel,
  });

  factory CowConfig.fromJson(Map<String, Object?> json) =>
      _$CowConfigFromJson(json);

  /// Parses cow.json. Returns default config if file doesn't exist or is
  /// empty. Throws [FormatException] on malformed JSON.
  factory CowConfig.fromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return const CowConfig();

    final content = file.readAsStringSync().trim();
    if (content.isEmpty) return const CowConfig();

    final json = jsonDecode(content);
    if (json is! Map<String, Object?>) {
      throw FormatException('Expected a JSON object in $path');
    }

    return CowConfig.fromJson(json);
  }

  final Map<String, CowModelConfig> models;
  final String? primaryModel;
  final String? lightweightModel;

  Map<String, Object?> toJson() => _$CowConfigToJson(this);
}

/// Config for a single model entry in cow.json.
@JsonSerializable(explicitToJson: true)
class CowModelConfig {
  const CowModelConfig({
    this.files,
    this.entrypointFileName,
    this.modelFamily,
    this.backend,
    this.supportsReasoning,
    this.runtimeConfig,
  });

  factory CowModelConfig.fromJson(Map<String, Object?> json) =>
      _$CowModelConfigFromJson(json);

  final List<CowModelFileConfig>? files;
  final String? entrypointFileName;
  final String? modelFamily;
  final String? backend;
  final bool? supportsReasoning;
  final ModelRuntimeConfig? runtimeConfig;

  Map<String, Object?> toJson() => _$CowModelConfigToJson(this);
}

@JsonSerializable()
class CowModelFileConfig {
  const CowModelFileConfig({required this.url, required this.fileName});

  factory CowModelFileConfig.fromJson(Map<String, Object?> json) =>
      _$CowModelFileConfigFromJson(json);

  final String url;
  final String fileName;

  Map<String, Object?> toJson() => _$CowModelFileConfigToJson(this);
}
