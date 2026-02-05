// Messages for ModelServer isolate communication.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/isolate/models.dart';
import 'package:json_annotation/json_annotation.dart';

part 'model_server_messages.g.dart';

@JsonEnum(alwaysCreate: true)
enum ModelServerRequestType {
  @JsonValue('load_model')
  loadModel,
  @JsonValue('unload_model')
  unloadModel,
  @JsonValue('dispose')
  dispose,
}

@JsonEnum(alwaysCreate: true)
enum ModelServerResponseType {
  @JsonValue('model_loaded')
  modelLoaded,
  @JsonValue('model_unloaded')
  modelUnloaded,
  @JsonValue('load_progress')
  loadProgress,
  @JsonValue('error')
  error,
}

sealed class ModelServerRequest {
  const ModelServerRequest();

  factory ModelServerRequest.fromJson(Map<String, Object?> json) {
    final type = $enumDecode(_$ModelServerRequestTypeEnumMap, json['type']);
    return switch (type) {
      ModelServerRequestType.loadModel => LoadModelRequest.fromJson(json),
      ModelServerRequestType.unloadModel => UnloadModelRequest.fromJson(json),
      ModelServerRequestType.dispose => DisposeModelServerRequest.fromJson(
        json,
      ),
    };
  }

  ModelServerRequestType get type;
  Map<String, Object?> toJson();
}

@JsonSerializable(explicitToJson: true)
final class LoadModelRequest extends ModelServerRequest {
  const LoadModelRequest({
    required this.modelPath,
    required this.libraryPath,
    this.modelOptions = const LlamaModelOptions(),
    this.type = ModelServerRequestType.loadModel,
  });

  factory LoadModelRequest.fromJson(Map<String, Object?> json) =>
      _$LoadModelRequestFromJson(json);

  @override
  final ModelServerRequestType type;
  final String modelPath;
  final String libraryPath;
  final LlamaModelOptions modelOptions;

  @override
  Map<String, Object?> toJson() => _$LoadModelRequestToJson(this);
}

@JsonSerializable()
final class UnloadModelRequest extends ModelServerRequest {
  const UnloadModelRequest({
    required this.modelPath,
    this.type = ModelServerRequestType.unloadModel,
  });

  factory UnloadModelRequest.fromJson(Map<String, Object?> json) =>
      _$UnloadModelRequestFromJson(json);

  @override
  final ModelServerRequestType type;
  final String modelPath;

  @override
  Map<String, Object?> toJson() => _$UnloadModelRequestToJson(this);
}

@JsonSerializable()
final class DisposeModelServerRequest extends ModelServerRequest {
  const DisposeModelServerRequest({
    this.type = ModelServerRequestType.dispose,
  });

  factory DisposeModelServerRequest.fromJson(Map<String, Object?> json) =>
      _$DisposeModelServerRequestFromJson(json);

  @override
  final ModelServerRequestType type;

  @override
  Map<String, Object?> toJson() => _$DisposeModelServerRequestToJson(this);
}

sealed class ModelServerResponse {
  const ModelServerResponse();

  factory ModelServerResponse.fromJson(Map<String, Object?> json) {
    final type = $enumDecode(_$ModelServerResponseTypeEnumMap, json['type']);
    return switch (type) {
      ModelServerResponseType.modelLoaded => ModelLoadedResponse.fromJson(json),
      ModelServerResponseType.modelUnloaded => ModelUnloadedResponse.fromJson(
        json,
      ),
      ModelServerResponseType.loadProgress => LoadProgressResponse.fromJson(
        json,
      ),
      ModelServerResponseType.error => ModelServerError.fromJson(json),
    };
  }

  ModelServerResponseType get type;
  Map<String, Object?> toJson();
}

@JsonSerializable()
final class ModelLoadedResponse extends ModelServerResponse {
  const ModelLoadedResponse({
    required this.modelPath,
    required this.modelPointer,
    this.type = ModelServerResponseType.modelLoaded,
  });

  factory ModelLoadedResponse.fromJson(Map<String, Object?> json) =>
      _$ModelLoadedResponseFromJson(json);

  @override
  final ModelServerResponseType type;
  final String modelPath;
  final int modelPointer;

  @override
  Map<String, Object?> toJson() => _$ModelLoadedResponseToJson(this);
}

@JsonSerializable()
final class ModelUnloadedResponse extends ModelServerResponse {
  const ModelUnloadedResponse({
    required this.modelPath,
    this.type = ModelServerResponseType.modelUnloaded,
  });

  factory ModelUnloadedResponse.fromJson(Map<String, Object?> json) =>
      _$ModelUnloadedResponseFromJson(json);

  @override
  final ModelServerResponseType type;
  final String modelPath;

  @override
  Map<String, Object?> toJson() => _$ModelUnloadedResponseToJson(this);
}

@JsonSerializable()
final class LoadProgressResponse extends ModelServerResponse {
  const LoadProgressResponse({
    required this.modelPath,
    required this.progress,
    this.type = ModelServerResponseType.loadProgress,
  });

  factory LoadProgressResponse.fromJson(Map<String, Object?> json) =>
      _$LoadProgressResponseFromJson(json);

  @override
  final ModelServerResponseType type;
  final String modelPath;
  final double progress;

  @override
  Map<String, Object?> toJson() => _$LoadProgressResponseToJson(this);
}

@JsonSerializable()
final class ModelServerError extends ModelServerResponse {
  const ModelServerError({
    required this.error,
    this.type = ModelServerResponseType.error,
  });

  factory ModelServerError.fromJson(Map<String, Object?> json) =>
      _$ModelServerErrorFromJson(json);

  @override
  final ModelServerResponseType type;
  final String error;

  @override
  Map<String, Object?> toJson() => _$ModelServerErrorToJson(this);
}
