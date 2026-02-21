// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_runtime_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ModelRuntimeConfig _$ModelRuntimeConfigFromJson(Map<String, dynamic> json) =>
    ModelRuntimeConfig(
      contextSize: (json['contextSize'] as num?)?.toInt(),
      temperature: (json['temperature'] as num?)?.toDouble(),
      topK: (json['topK'] as num?)?.toInt(),
      topP: (json['topP'] as num?)?.toDouble(),
      minP: (json['minP'] as num?)?.toDouble(),
      penaltyRepeat: (json['penaltyRepeat'] as num?)?.toDouble(),
      penaltyLastN: (json['penaltyLastN'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ModelRuntimeConfigToJson(ModelRuntimeConfig instance) =>
    <String, dynamic>{
      'contextSize': instance.contextSize,
      'temperature': instance.temperature,
      'topK': instance.topK,
      'topP': instance.topP,
      'minP': instance.minP,
      'penaltyRepeat': instance.penaltyRepeat,
      'penaltyLastN': instance.penaltyLastN,
    };
