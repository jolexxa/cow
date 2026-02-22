// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_server_messages.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LoadModelRequest _$LoadModelRequestFromJson(Map<String, dynamic> json) =>
    LoadModelRequest(
      modelPath: json['modelPath'] as String,
      libraryPath: json['libraryPath'] as String,
      modelOptions: json['modelOptions'] == null
          ? const LlamaModelOptions()
          : LlamaModelOptions.fromJson(
              json['modelOptions'] as Map<String, dynamic>,
            ),
      backend:
          $enumDecodeNullable(
            _$InferenceBackendEnumMap,
            json['backend'],
            unknownValue: InferenceBackend.llamaCpp,
          ) ??
          InferenceBackend.llamaCpp,
      type:
          $enumDecodeNullable(_$ModelServerRequestTypeEnumMap, json['type']) ??
          ModelServerRequestType.loadModel,
    );

Map<String, dynamic> _$LoadModelRequestToJson(LoadModelRequest instance) =>
    <String, dynamic>{
      'type': _$ModelServerRequestTypeEnumMap[instance.type]!,
      'modelPath': instance.modelPath,
      'libraryPath': instance.libraryPath,
      'modelOptions': instance.modelOptions.toJson(),
      'backend': _$InferenceBackendEnumMap[instance.backend]!,
    };

const _$InferenceBackendEnumMap = {
  InferenceBackend.llamaCpp: 'llama_cpp',
  InferenceBackend.mlx: 'mlx',
};

const _$ModelServerRequestTypeEnumMap = {
  ModelServerRequestType.loadModel: 'load_model',
  ModelServerRequestType.unloadModel: 'unload_model',
  ModelServerRequestType.dispose: 'dispose',
};

UnloadModelRequest _$UnloadModelRequestFromJson(Map<String, dynamic> json) =>
    UnloadModelRequest(
      modelPath: json['modelPath'] as String,
      type:
          $enumDecodeNullable(_$ModelServerRequestTypeEnumMap, json['type']) ??
          ModelServerRequestType.unloadModel,
    );

Map<String, dynamic> _$UnloadModelRequestToJson(UnloadModelRequest instance) =>
    <String, dynamic>{
      'type': _$ModelServerRequestTypeEnumMap[instance.type]!,
      'modelPath': instance.modelPath,
    };

DisposeModelServerRequest _$DisposeModelServerRequestFromJson(
  Map<String, dynamic> json,
) => DisposeModelServerRequest(
  type:
      $enumDecodeNullable(_$ModelServerRequestTypeEnumMap, json['type']) ??
      ModelServerRequestType.dispose,
);

Map<String, dynamic> _$DisposeModelServerRequestToJson(
  DisposeModelServerRequest instance,
) => <String, dynamic>{'type': _$ModelServerRequestTypeEnumMap[instance.type]!};

ModelLoadedResponse _$ModelLoadedResponseFromJson(Map<String, dynamic> json) =>
    ModelLoadedResponse(
      modelPath: json['modelPath'] as String,
      modelPointer: (json['modelPointer'] as num).toInt(),
      type:
          $enumDecodeNullable(_$ModelServerResponseTypeEnumMap, json['type']) ??
          ModelServerResponseType.modelLoaded,
    );

Map<String, dynamic> _$ModelLoadedResponseToJson(
  ModelLoadedResponse instance,
) => <String, dynamic>{
  'type': _$ModelServerResponseTypeEnumMap[instance.type]!,
  'modelPath': instance.modelPath,
  'modelPointer': instance.modelPointer,
};

const _$ModelServerResponseTypeEnumMap = {
  ModelServerResponseType.modelLoaded: 'model_loaded',
  ModelServerResponseType.modelUnloaded: 'model_unloaded',
  ModelServerResponseType.loadProgress: 'load_progress',
  ModelServerResponseType.error: 'error',
};

ModelUnloadedResponse _$ModelUnloadedResponseFromJson(
  Map<String, dynamic> json,
) => ModelUnloadedResponse(
  modelPath: json['modelPath'] as String,
  type:
      $enumDecodeNullable(_$ModelServerResponseTypeEnumMap, json['type']) ??
      ModelServerResponseType.modelUnloaded,
);

Map<String, dynamic> _$ModelUnloadedResponseToJson(
  ModelUnloadedResponse instance,
) => <String, dynamic>{
  'type': _$ModelServerResponseTypeEnumMap[instance.type]!,
  'modelPath': instance.modelPath,
};

LoadProgressResponse _$LoadProgressResponseFromJson(
  Map<String, dynamic> json,
) => LoadProgressResponse(
  modelPath: json['modelPath'] as String,
  progress: (json['progress'] as num).toDouble(),
  type:
      $enumDecodeNullable(_$ModelServerResponseTypeEnumMap, json['type']) ??
      ModelServerResponseType.loadProgress,
);

Map<String, dynamic> _$LoadProgressResponseToJson(
  LoadProgressResponse instance,
) => <String, dynamic>{
  'type': _$ModelServerResponseTypeEnumMap[instance.type]!,
  'modelPath': instance.modelPath,
  'progress': instance.progress,
};

ModelServerError _$ModelServerErrorFromJson(Map<String, dynamic> json) =>
    ModelServerError(
      error: json['error'] as String,
      type:
          $enumDecodeNullable(_$ModelServerResponseTypeEnumMap, json['type']) ??
          ModelServerResponseType.error,
    );

Map<String, dynamic> _$ModelServerErrorToJson(ModelServerError instance) =>
    <String, dynamic>{
      'type': _$ModelServerResponseTypeEnumMap[instance.type]!,
      'error': instance.error,
    };
