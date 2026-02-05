// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cow_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CowConfig _$CowConfigFromJson(Map<String, dynamic> json) => CowConfig(
  models:
      (json['models'] as Map<String, dynamic>?)?.map(
        (k, e) =>
            MapEntry(k, CowModelConfig.fromJson(e as Map<String, dynamic>)),
      ) ??
      const {},
  primaryModel: json['primaryModel'] as String?,
  lightweightModel: json['lightweightModel'] as String?,
);

Map<String, dynamic> _$CowConfigToJson(CowConfig instance) => <String, dynamic>{
  'models': instance.models.map((k, e) => MapEntry(k, e.toJson())),
  'primaryModel': instance.primaryModel,
  'lightweightModel': instance.lightweightModel,
};

CowModelConfig _$CowModelConfigFromJson(Map<String, dynamic> json) =>
    CowModelConfig(
      files: (json['files'] as List<dynamic>?)
          ?.map((e) => CowModelFileConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
      entrypointFileName: json['entrypointFileName'] as String?,
      modelFamily: json['modelFamily'] as String?,
      supportsReasoning: json['supportsReasoning'] as bool?,
      runtimeConfig: json['runtimeConfig'] == null
          ? null
          : ModelRuntimeConfig.fromJson(
              json['runtimeConfig'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$CowModelConfigToJson(CowModelConfig instance) =>
    <String, dynamic>{
      'files': instance.files?.map((e) => e.toJson()).toList(),
      'entrypointFileName': instance.entrypointFileName,
      'modelFamily': instance.modelFamily,
      'supportsReasoning': instance.supportsReasoning,
      'runtimeConfig': instance.runtimeConfig?.toJson(),
    };

CowModelFileConfig _$CowModelFileConfigFromJson(Map<String, dynamic> json) =>
    CowModelFileConfig(
      url: json['url'] as String,
      fileName: json['fileName'] as String,
    );

Map<String, dynamic> _$CowModelFileConfigToJson(CowModelFileConfig instance) =>
    <String, dynamic>{'url': instance.url, 'fileName': instance.fileName};
