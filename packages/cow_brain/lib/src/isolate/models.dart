// Isolate boundary DTOs for serializable messaging.
// Still designing api's.
// ignore_for_file: public_member_api_docs

import 'package:json_annotation/json_annotation.dart';

part 'models.g.dart';

@JsonEnum(alwaysCreate: true)
enum Role {
  @JsonValue('system')
  system,
  @JsonValue('user')
  user,
  @JsonValue('assistant')
  assistant,
  @JsonValue('tool')
  tool,
}

@JsonEnum(alwaysCreate: true)
enum FinishReason {
  @JsonValue('stop')
  stop,
  @JsonValue('length')
  length,
  @JsonValue('tool_calls')
  toolCalls,
  @JsonValue('error')
  error,
  @JsonValue('cancelled')
  cancelled,
  @JsonValue('max_steps')
  maxSteps,
}

@JsonEnum(alwaysCreate: true)
enum LlamaProfileId {
  @JsonValue('qwen3')
  qwen3,
  @JsonValue('qwen25')
  qwen25,
  @JsonValue('qwen25_3b')
  qwen25_3b,
}

@JsonEnum(alwaysCreate: true)
enum AgentEventType {
  @JsonValue('ready')
  ready,
  @JsonValue('step_started')
  stepStarted,
  @JsonValue('context_trimmed')
  contextTrimmed,
  @JsonValue('telemetry_update')
  telemetryUpdate,
  @JsonValue('text_delta')
  textDelta,
  @JsonValue('reasoning_delta')
  reasoningDelta,
  @JsonValue('tool_calls')
  toolCalls,
  @JsonValue('tool_result')
  toolResult,
  @JsonValue('step_finished')
  stepFinished,
  @JsonValue('turn_finished')
  turnFinished,
  @JsonValue('error')
  error,
}

@JsonEnum(alwaysCreate: true)
enum BrainRequestType {
  @JsonValue('init')
  init,
  @JsonValue('run_turn')
  runTurn,
  @JsonValue('tool_result')
  toolResult,
  @JsonValue('cancel')
  cancel,
  @JsonValue('reset')
  reset,
  @JsonValue('dispose')
  dispose,
}

@JsonSerializable(explicitToJson: true)
class Message {
  const Message({
    required this.role,
    required this.content,
    this.reasoningContent,
    this.toolCalls = const <ToolCall>[],
    this.toolCallId,
    this.name,
  });
  factory Message.fromJson(Map<String, Object?> json) =>
      _$MessageFromJson(json);
  final Role role;
  final String content;
  final String? reasoningContent;
  final List<ToolCall> toolCalls;
  final String? toolCallId;
  final String? name;
  Map<String, Object?> toJson() => _$MessageToJson(this);
}

@JsonSerializable()
class ToolDefinition {
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });
  factory ToolDefinition.fromJson(Map<String, Object?> json) =>
      _$ToolDefinitionFromJson(json);
  final String name;
  final String description;
  final Map<String, Object?> parameters;
  Map<String, Object?> toJson() => _$ToolDefinitionToJson(this);
}

@JsonSerializable()
class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
  factory ToolCall.fromJson(Map<String, Object?> json) =>
      _$ToolCallFromJson(json);
  final String id;
  final String name;
  final Map<String, Object?> arguments;
  Map<String, Object?> toJson() => _$ToolCallToJson(this);
}

@JsonSerializable()
class ToolResult {
  const ToolResult({
    required this.toolCallId,
    required this.name,
    required this.content,
    this.isError = false,
    this.errorMessage,
  });
  factory ToolResult.fromJson(Map<String, Object?> json) =>
      _$ToolResultFromJson(json);
  final String toolCallId;
  final String name;
  final String content;
  final bool isError;
  final String? errorMessage;
  Map<String, Object?> toJson() => _$ToolResultToJson(this);
}

@JsonSerializable()
class LlmConfig {
  const LlmConfig({
    required this.requiresReset,
    required this.reusePrefixMessageCount,
  });
  factory LlmConfig.fromJson(Map<String, Object?> json) =>
      _$LlmConfigFromJson(json);
  final bool requiresReset;
  final int reusePrefixMessageCount;
  Map<String, Object?> toJson() => _$LlmConfigToJson(this);
}

@JsonSerializable(explicitToJson: true)
class LlamaRuntimeOptions {
  const LlamaRuntimeOptions({
    required this.modelPath,
    required this.contextOptions,
    required this.libraryPath,
    this.modelOptions = const LlamaModelOptions(),
    this.samplingOptions = const LlamaSamplingOptions(),
    this.maxOutputTokensDefault = 512,
  });
  factory LlamaRuntimeOptions.fromJson(Map<String, Object?> json) =>
      _$LlamaRuntimeOptionsFromJson(json);
  final String modelPath;
  final LlamaModelOptions modelOptions;
  final LlamaContextOptions contextOptions;
  final LlamaSamplingOptions samplingOptions;
  final int maxOutputTokensDefault;
  final String libraryPath;
  Map<String, Object?> toJson() => _$LlamaRuntimeOptionsToJson(this);
}

@JsonSerializable()
class LlamaModelOptions {
  const LlamaModelOptions({
    this.nGpuLayers,
    this.mainGpu,
    this.numa,
    this.useMmap,
    this.useMlock,
    this.checkTensors,
  });
  factory LlamaModelOptions.fromJson(Map<String, Object?> json) =>
      _$LlamaModelOptionsFromJson(json);
  final int? nGpuLayers;
  final int? mainGpu;
  final int? numa;
  final bool? useMmap;
  final bool? useMlock;
  final bool? checkTensors;
  Map<String, Object?> toJson() => _$LlamaModelOptionsToJson(this);
}

@JsonSerializable()
class LlamaContextOptions {
  const LlamaContextOptions({
    required this.contextSize,
    required this.nBatch,
    required this.nThreads,
    required this.nThreadsBatch,
    this.useFlashAttn,
  });
  factory LlamaContextOptions.fromJson(Map<String, Object?> json) =>
      _$LlamaContextOptionsFromJson(json);
  final int contextSize;
  final int nBatch;
  final int nThreads;
  final int nThreadsBatch;
  final bool? useFlashAttn;
  Map<String, Object?> toJson() => _$LlamaContextOptionsToJson(this);
}

@JsonSerializable()
class LlamaSamplingOptions {
  const LlamaSamplingOptions({
    this.seed = 0,
    this.topK,
    this.topP,
    this.minP,
    this.temperature,
    this.typicalP,
    this.penaltyRepeat,
    this.penaltyLastN,
  });
  factory LlamaSamplingOptions.fromJson(Map<String, Object?> json) =>
      _$LlamaSamplingOptionsFromJson(json);
  final int seed;
  final int? topK;
  final double? topP;
  final double? minP;
  final double? temperature;
  final double? typicalP;
  final double? penaltyRepeat;
  final int? penaltyLastN;
  Map<String, Object?> toJson() => _$LlamaSamplingOptionsToJson(this);
}

@JsonSerializable()
class AgentSettings {
  const AgentSettings({
    required this.safetyMarginTokens,
    required this.maxSteps,
  });
  factory AgentSettings.fromJson(Map<String, Object?> json) =>
      _$AgentSettingsFromJson(json);
  final int safetyMarginTokens;
  final int maxSteps;
  Map<String, Object?> toJson() => _$AgentSettingsToJson(this);
}

@JsonSerializable(explicitToJson: true)
class InitRequest {
  const InitRequest({
    required this.runtimeOptions,
    required this.profile,
    required this.tools,
    required this.settings,
    required this.enableReasoning,
  });
  factory InitRequest.fromJson(Map<String, Object?> json) =>
      _$InitRequestFromJson(json);
  final LlamaRuntimeOptions runtimeOptions;
  @JsonKey(unknownEnumValue: LlamaProfileId.qwen3)
  final LlamaProfileId profile;
  final List<ToolDefinition> tools;
  final AgentSettings settings;
  final bool enableReasoning;
  Map<String, Object?> toJson() => _$InitRequestToJson(this);
}

@JsonSerializable(explicitToJson: true)
class RunTurnRequest {
  const RunTurnRequest({
    required this.userMessage,
    required this.settings,
    required this.enableReasoning,
  });
  factory RunTurnRequest.fromJson(Map<String, Object?> json) =>
      _$RunTurnRequestFromJson(json);
  final Message userMessage;
  final AgentSettings settings;
  final bool enableReasoning;
  Map<String, Object?> toJson() => _$RunTurnRequestToJson(this);
}

@JsonSerializable(explicitToJson: true)
class ToolResultRequest {
  const ToolResultRequest({required this.turnId, required this.toolResult});
  factory ToolResultRequest.fromJson(Map<String, Object?> json) =>
      _$ToolResultRequestFromJson(json);
  final String turnId;
  final ToolResult toolResult;
  Map<String, Object?> toJson() => _$ToolResultRequestToJson(this);
}

@JsonSerializable()
class CancelRequest {
  const CancelRequest({required this.turnId});
  factory CancelRequest.fromJson(Map<String, Object?> json) =>
      _$CancelRequestFromJson(json);
  final String turnId;
  Map<String, Object?> toJson() => _$CancelRequestToJson(this);
}

@JsonSerializable(explicitToJson: true)
class BrainRequest {
  const BrainRequest({
    required this.type,
    this.init,
    this.runTurn,
    this.toolResult,
    this.cancel,
  });
  factory BrainRequest.fromJson(Map<String, Object?> json) =>
      _$BrainRequestFromJson(json);
  final BrainRequestType type;
  final InitRequest? init;
  final RunTurnRequest? runTurn;
  final ToolResultRequest? toolResult;
  final CancelRequest? cancel;
  Map<String, Object?> toJson() => _$BrainRequestToJson(this);
}

sealed class AgentEvent {
  const AgentEvent();
  factory AgentEvent.fromJson(Map<String, Object?> json) {
    final type = $enumDecode(_$AgentEventTypeEnumMap, json['type']);
    return switch (type) {
      AgentEventType.ready => AgentReady.fromJson(json),
      AgentEventType.stepStarted => AgentStepStarted.fromJson(json),
      AgentEventType.contextTrimmed => AgentContextTrimmed.fromJson(json),
      AgentEventType.telemetryUpdate => AgentTelemetryUpdate.fromJson(json),
      AgentEventType.textDelta => AgentTextDelta.fromJson(json),
      AgentEventType.reasoningDelta => AgentReasoningDelta.fromJson(json),
      AgentEventType.toolCalls => AgentToolCalls.fromJson(json),
      AgentEventType.toolResult => AgentToolResult.fromJson(json),
      AgentEventType.stepFinished => AgentStepFinished.fromJson(json),
      AgentEventType.turnFinished => AgentTurnFinished.fromJson(json),
      AgentEventType.error => AgentError.fromJson(json),
    };
  }
  AgentEventType get type;
  String? get turnId;
  int? get step;
  Map<String, Object?> toJson();
}

@JsonSerializable()
final class AgentReady extends AgentEvent {
  const AgentReady({this.type = AgentEventType.ready});
  factory AgentReady.fromJson(Map<String, Object?> json) =>
      _$AgentReadyFromJson(json);
  @override
  final AgentEventType type;
  @override
  String? get turnId => null;
  @override
  int? get step => null;
  @override
  Map<String, Object?> toJson() => _$AgentReadyToJson(this);
}

@JsonSerializable()
final class AgentStepStarted extends AgentEvent {
  const AgentStepStarted({
    required this.turnId,
    required this.step,
    this.type = AgentEventType.stepStarted,
  });
  factory AgentStepStarted.fromJson(Map<String, Object?> json) =>
      _$AgentStepStartedFromJson(json);
  @override
  final AgentEventType type;
  @override
  final String turnId;
  @override
  final int step;
  @override
  Map<String, Object?> toJson() => _$AgentStepStartedToJson(this);
}

@JsonSerializable()
final class AgentContextTrimmed extends AgentEvent {
  const AgentContextTrimmed({
    required this.turnId,
    required this.step,
    required this.droppedMessageCount,
    this.type = AgentEventType.contextTrimmed,
  });
  factory AgentContextTrimmed.fromJson(Map<String, Object?> json) =>
      _$AgentContextTrimmedFromJson(json);
  @override
  final AgentEventType type;
  @override
  final String turnId;
  @override
  final int step;
  final int droppedMessageCount;
  @override
  Map<String, Object?> toJson() => _$AgentContextTrimmedToJson(this);
}

@JsonSerializable()
final class AgentTelemetryUpdate extends AgentEvent {
  const AgentTelemetryUpdate({
    required this.turnId,
    required this.step,
    required this.promptTokens,
    required this.budgetTokens,
    required this.remainingTokens,
    required this.contextSize,
    required this.maxOutputTokens,
    required this.safetyMarginTokens,
    this.type = AgentEventType.telemetryUpdate,
  });
  factory AgentTelemetryUpdate.fromJson(Map<String, Object?> json) =>
      _$AgentTelemetryUpdateFromJson(json);
  @override
  final AgentEventType type;
  @override
  final String turnId;
  @override
  final int step;
  final int promptTokens;
  final int budgetTokens;
  final int remainingTokens;
  final int contextSize;
  final int maxOutputTokens;
  final int safetyMarginTokens;
  @override
  Map<String, Object?> toJson() => _$AgentTelemetryUpdateToJson(this);
}

@JsonSerializable()
final class AgentTextDelta extends AgentEvent {
  const AgentTextDelta({
    required this.turnId,
    required this.step,
    required this.text,
    this.type = AgentEventType.textDelta,
  });
  factory AgentTextDelta.fromJson(Map<String, Object?> json) =>
      _$AgentTextDeltaFromJson(json);
  @override
  final AgentEventType type;
  @override
  final String turnId;
  @override
  final int step;
  final String text;
  @override
  Map<String, Object?> toJson() => _$AgentTextDeltaToJson(this);
}

@JsonSerializable()
final class AgentReasoningDelta extends AgentEvent {
  const AgentReasoningDelta({
    required this.turnId,
    required this.step,
    required this.text,
    this.type = AgentEventType.reasoningDelta,
  });
  factory AgentReasoningDelta.fromJson(Map<String, Object?> json) =>
      _$AgentReasoningDeltaFromJson(json);
  @override
  final AgentEventType type;
  @override
  final String turnId;
  @override
  final int step;
  final String text;
  @override
  Map<String, Object?> toJson() => _$AgentReasoningDeltaToJson(this);
}

@JsonSerializable(explicitToJson: true)
final class AgentToolCalls extends AgentEvent {
  const AgentToolCalls({
    required this.turnId,
    required this.step,
    required this.calls,
    required this.finishReason,
    this.preToolText,
    this.preToolReasoning,
    this.type = AgentEventType.toolCalls,
  });
  factory AgentToolCalls.fromJson(Map<String, Object?> json) =>
      _$AgentToolCallsFromJson(json);
  @override
  final AgentEventType type;
  @override
  final String turnId;
  @override
  final int step;
  final List<ToolCall> calls;
  final FinishReason finishReason;
  final String? preToolText;
  final String? preToolReasoning;
  @override
  Map<String, Object?> toJson() => _$AgentToolCallsToJson(this);
}

@JsonSerializable(explicitToJson: true)
final class AgentToolResult extends AgentEvent {
  const AgentToolResult({
    required this.turnId,
    required this.step,
    required this.result,
    this.type = AgentEventType.toolResult,
  });
  factory AgentToolResult.fromJson(Map<String, Object?> json) =>
      _$AgentToolResultFromJson(json);
  @override
  final AgentEventType type;
  @override
  final String turnId;
  @override
  final int step;
  final ToolResult result;
  @override
  Map<String, Object?> toJson() => _$AgentToolResultToJson(this);
}

@JsonSerializable()
final class AgentStepFinished extends AgentEvent {
  const AgentStepFinished({
    required this.turnId,
    required this.step,
    required this.text,
    required this.finishReason,
    this.reasoning,
    this.type = AgentEventType.stepFinished,
  });
  factory AgentStepFinished.fromJson(Map<String, Object?> json) =>
      _$AgentStepFinishedFromJson(json);
  @override
  final AgentEventType type;
  @override
  final String turnId;
  @override
  final int step;
  final String text;
  final FinishReason finishReason;
  final String? reasoning;
  @override
  Map<String, Object?> toJson() => _$AgentStepFinishedToJson(this);
}

@JsonSerializable()
final class AgentTurnFinished extends AgentEvent {
  const AgentTurnFinished({
    required this.turnId,
    required this.step,
    required this.finishReason,
    this.type = AgentEventType.turnFinished,
  });
  factory AgentTurnFinished.fromJson(Map<String, Object?> json) =>
      _$AgentTurnFinishedFromJson(json);
  @override
  final AgentEventType type;
  @override
  final String turnId;
  @override
  final int step;
  final FinishReason finishReason;
  @override
  Map<String, Object?> toJson() => _$AgentTurnFinishedToJson(this);
}

@JsonSerializable()
final class AgentError extends AgentEvent {
  const AgentError({
    required this.error,
    this.turnId,
    this.step,
    this.type = AgentEventType.error,
  });
  factory AgentError.fromJson(Map<String, Object?> json) =>
      _$AgentErrorFromJson(json);
  @override
  final AgentEventType type;
  @override
  final String? turnId;
  @override
  final int? step;
  final String error;
  @override
  Map<String, Object?> toJson() => _$AgentErrorToJson(this);
}
