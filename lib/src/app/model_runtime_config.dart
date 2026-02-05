import 'package:json_annotation/json_annotation.dart';

part 'model_runtime_config.g.dart';

/// Per-model runtime configuration.
///
/// All fields are nullable — null means "use the default value."
@JsonSerializable()
class ModelRuntimeConfig {
  const ModelRuntimeConfig({
    this.contextSize,
    this.temperature,
    this.topK,
    this.topP,
    this.minP,
    this.penaltyRepeat,
    this.penaltyLastN,
  });

  factory ModelRuntimeConfig.fromJson(Map<String, Object?> json) =>
      _$ModelRuntimeConfigFromJson(json);

  final int? contextSize;
  final double? temperature;
  final int? topK;
  final double? topP;
  final double? minP;
  final double? penaltyRepeat;
  final int? penaltyLastN;

  Map<String, Object?> toJson() => _$ModelRuntimeConfigToJson(this);

  /// Merges [other] on top of this config. Non-null values in [other] win.
  ModelRuntimeConfig mergeWith(ModelRuntimeConfig? other) {
    if (other == null) return this;
    return ModelRuntimeConfig(
      contextSize: other.contextSize ?? contextSize,
      temperature: other.temperature ?? temperature,
      topK: other.topK ?? topK,
      topP: other.topP ?? topP,
      minP: other.minP ?? minP,
      penaltyRepeat: other.penaltyRepeat ?? penaltyRepeat,
      penaltyLastN: other.penaltyLastN ?? penaltyLastN,
    );
  }
}
