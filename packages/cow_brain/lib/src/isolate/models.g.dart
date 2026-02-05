// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Message _$MessageFromJson(Map<String, dynamic> json) => Message(
  role: $enumDecode(_$RoleEnumMap, json['role']),
  content: json['content'] as String,
  reasoningContent: json['reasoningContent'] as String?,
  toolCalls:
      (json['toolCalls'] as List<dynamic>?)
          ?.map((e) => ToolCall.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <ToolCall>[],
  toolCallId: json['toolCallId'] as String?,
  name: json['name'] as String?,
);

Map<String, dynamic> _$MessageToJson(Message instance) => <String, dynamic>{
  'role': _$RoleEnumMap[instance.role]!,
  'content': instance.content,
  'reasoningContent': instance.reasoningContent,
  'toolCalls': instance.toolCalls.map((e) => e.toJson()).toList(),
  'toolCallId': instance.toolCallId,
  'name': instance.name,
};

const _$RoleEnumMap = {
  Role.system: 'system',
  Role.user: 'user',
  Role.assistant: 'assistant',
  Role.tool: 'tool',
};

ToolDefinition _$ToolDefinitionFromJson(Map<String, dynamic> json) =>
    ToolDefinition(
      name: json['name'] as String,
      description: json['description'] as String,
      parameters: json['parameters'] as Map<String, dynamic>,
    );

Map<String, dynamic> _$ToolDefinitionToJson(ToolDefinition instance) =>
    <String, dynamic>{
      'name': instance.name,
      'description': instance.description,
      'parameters': instance.parameters,
    };

ToolCall _$ToolCallFromJson(Map<String, dynamic> json) => ToolCall(
  id: json['id'] as String,
  name: json['name'] as String,
  arguments: json['arguments'] as Map<String, dynamic>,
);

Map<String, dynamic> _$ToolCallToJson(ToolCall instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'arguments': instance.arguments,
};

ToolResult _$ToolResultFromJson(Map<String, dynamic> json) => ToolResult(
  toolCallId: json['toolCallId'] as String,
  name: json['name'] as String,
  content: json['content'] as String,
  isError: json['isError'] as bool? ?? false,
  errorMessage: json['errorMessage'] as String?,
);

Map<String, dynamic> _$ToolResultToJson(ToolResult instance) =>
    <String, dynamic>{
      'toolCallId': instance.toolCallId,
      'name': instance.name,
      'content': instance.content,
      'isError': instance.isError,
      'errorMessage': instance.errorMessage,
    };

LlmConfig _$LlmConfigFromJson(Map<String, dynamic> json) => LlmConfig(
  requiresReset: json['requiresReset'] as bool,
  reusePrefixMessageCount: (json['reusePrefixMessageCount'] as num).toInt(),
);

Map<String, dynamic> _$LlmConfigToJson(LlmConfig instance) => <String, dynamic>{
  'requiresReset': instance.requiresReset,
  'reusePrefixMessageCount': instance.reusePrefixMessageCount,
};

LlamaRuntimeOptions _$LlamaRuntimeOptionsFromJson(Map<String, dynamic> json) =>
    LlamaRuntimeOptions(
      modelPath: json['modelPath'] as String,
      contextOptions: LlamaContextOptions.fromJson(
        json['contextOptions'] as Map<String, dynamic>,
      ),
      libraryPath: json['libraryPath'] as String,
      modelOptions: json['modelOptions'] == null
          ? const LlamaModelOptions()
          : LlamaModelOptions.fromJson(
              json['modelOptions'] as Map<String, dynamic>,
            ),
      samplingOptions: json['samplingOptions'] == null
          ? const LlamaSamplingOptions()
          : LlamaSamplingOptions.fromJson(
              json['samplingOptions'] as Map<String, dynamic>,
            ),
      maxOutputTokensDefault:
          (json['maxOutputTokensDefault'] as num?)?.toInt() ?? 512,
    );

Map<String, dynamic> _$LlamaRuntimeOptionsToJson(
  LlamaRuntimeOptions instance,
) => <String, dynamic>{
  'modelPath': instance.modelPath,
  'modelOptions': instance.modelOptions.toJson(),
  'contextOptions': instance.contextOptions.toJson(),
  'samplingOptions': instance.samplingOptions.toJson(),
  'maxOutputTokensDefault': instance.maxOutputTokensDefault,
  'libraryPath': instance.libraryPath,
};

LlamaModelOptions _$LlamaModelOptionsFromJson(Map<String, dynamic> json) =>
    LlamaModelOptions(
      nGpuLayers: (json['nGpuLayers'] as num?)?.toInt(),
      mainGpu: (json['mainGpu'] as num?)?.toInt(),
      numa: (json['numa'] as num?)?.toInt(),
      useMmap: json['useMmap'] as bool?,
      useMlock: json['useMlock'] as bool?,
      checkTensors: json['checkTensors'] as bool?,
    );

Map<String, dynamic> _$LlamaModelOptionsToJson(LlamaModelOptions instance) =>
    <String, dynamic>{
      'nGpuLayers': instance.nGpuLayers,
      'mainGpu': instance.mainGpu,
      'numa': instance.numa,
      'useMmap': instance.useMmap,
      'useMlock': instance.useMlock,
      'checkTensors': instance.checkTensors,
    };

LlamaContextOptions _$LlamaContextOptionsFromJson(Map<String, dynamic> json) =>
    LlamaContextOptions(
      contextSize: (json['contextSize'] as num).toInt(),
      nBatch: (json['nBatch'] as num).toInt(),
      nThreads: (json['nThreads'] as num).toInt(),
      nThreadsBatch: (json['nThreadsBatch'] as num).toInt(),
      useFlashAttn: json['useFlashAttn'] as bool?,
    );

Map<String, dynamic> _$LlamaContextOptionsToJson(
  LlamaContextOptions instance,
) => <String, dynamic>{
  'contextSize': instance.contextSize,
  'nBatch': instance.nBatch,
  'nThreads': instance.nThreads,
  'nThreadsBatch': instance.nThreadsBatch,
  'useFlashAttn': instance.useFlashAttn,
};

LlamaSamplingOptions _$LlamaSamplingOptionsFromJson(
  Map<String, dynamic> json,
) => LlamaSamplingOptions(
  seed: (json['seed'] as num?)?.toInt() ?? 0,
  topK: (json['topK'] as num?)?.toInt(),
  topP: (json['topP'] as num?)?.toDouble(),
  minP: (json['minP'] as num?)?.toDouble(),
  temperature: (json['temperature'] as num?)?.toDouble(),
  typicalP: (json['typicalP'] as num?)?.toDouble(),
  penaltyRepeat: (json['penaltyRepeat'] as num?)?.toDouble(),
  penaltyLastN: (json['penaltyLastN'] as num?)?.toInt(),
);

Map<String, dynamic> _$LlamaSamplingOptionsToJson(
  LlamaSamplingOptions instance,
) => <String, dynamic>{
  'seed': instance.seed,
  'topK': instance.topK,
  'topP': instance.topP,
  'minP': instance.minP,
  'temperature': instance.temperature,
  'typicalP': instance.typicalP,
  'penaltyRepeat': instance.penaltyRepeat,
  'penaltyLastN': instance.penaltyLastN,
};

AgentSettings _$AgentSettingsFromJson(Map<String, dynamic> json) =>
    AgentSettings(
      safetyMarginTokens: (json['safetyMarginTokens'] as num).toInt(),
      maxSteps: (json['maxSteps'] as num).toInt(),
    );

Map<String, dynamic> _$AgentSettingsToJson(AgentSettings instance) =>
    <String, dynamic>{
      'safetyMarginTokens': instance.safetyMarginTokens,
      'maxSteps': instance.maxSteps,
    };

InitRequest _$InitRequestFromJson(Map<String, dynamic> json) => InitRequest(
  modelPointer: (json['modelPointer'] as num).toInt(),
  runtimeOptions: LlamaRuntimeOptions.fromJson(
    json['runtimeOptions'] as Map<String, dynamic>,
  ),
  profile: $enumDecode(
    _$LlamaProfileIdEnumMap,
    json['profile'],
    unknownValue: LlamaProfileId.qwen3,
  ),
  tools: (json['tools'] as List<dynamic>)
      .map((e) => ToolDefinition.fromJson(e as Map<String, dynamic>))
      .toList(),
  settings: AgentSettings.fromJson(json['settings'] as Map<String, dynamic>),
  enableReasoning: json['enableReasoning'] as bool,
);

Map<String, dynamic> _$InitRequestToJson(InitRequest instance) =>
    <String, dynamic>{
      'modelPointer': instance.modelPointer,
      'runtimeOptions': instance.runtimeOptions.toJson(),
      'profile': _$LlamaProfileIdEnumMap[instance.profile]!,
      'tools': instance.tools.map((e) => e.toJson()).toList(),
      'settings': instance.settings.toJson(),
      'enableReasoning': instance.enableReasoning,
    };

const _$LlamaProfileIdEnumMap = {
  LlamaProfileId.qwen3: 'qwen3',
  LlamaProfileId.qwen25: 'qwen25',
  LlamaProfileId.auto: 'auto',
};

RunTurnRequest _$RunTurnRequestFromJson(
  Map<String, dynamic> json,
) => RunTurnRequest(
  userMessage: Message.fromJson(json['userMessage'] as Map<String, dynamic>),
  settings: AgentSettings.fromJson(json['settings'] as Map<String, dynamic>),
  enableReasoning: json['enableReasoning'] as bool,
);

Map<String, dynamic> _$RunTurnRequestToJson(RunTurnRequest instance) =>
    <String, dynamic>{
      'userMessage': instance.userMessage.toJson(),
      'settings': instance.settings.toJson(),
      'enableReasoning': instance.enableReasoning,
    };

ToolResultRequest _$ToolResultRequestFromJson(Map<String, dynamic> json) =>
    ToolResultRequest(
      turnId: json['turnId'] as String,
      toolResult: ToolResult.fromJson(
        json['toolResult'] as Map<String, dynamic>,
      ),
    );

Map<String, dynamic> _$ToolResultRequestToJson(ToolResultRequest instance) =>
    <String, dynamic>{
      'turnId': instance.turnId,
      'toolResult': instance.toolResult.toJson(),
    };

CancelRequest _$CancelRequestFromJson(Map<String, dynamic> json) =>
    CancelRequest(turnId: json['turnId'] as String);

Map<String, dynamic> _$CancelRequestToJson(CancelRequest instance) =>
    <String, dynamic>{'turnId': instance.turnId};

BrainRequest _$BrainRequestFromJson(Map<String, dynamic> json) => BrainRequest(
  type: $enumDecode(_$BrainRequestTypeEnumMap, json['type']),
  init: json['init'] == null
      ? null
      : InitRequest.fromJson(json['init'] as Map<String, dynamic>),
  runTurn: json['runTurn'] == null
      ? null
      : RunTurnRequest.fromJson(json['runTurn'] as Map<String, dynamic>),
  toolResult: json['toolResult'] == null
      ? null
      : ToolResultRequest.fromJson(json['toolResult'] as Map<String, dynamic>),
  cancel: json['cancel'] == null
      ? null
      : CancelRequest.fromJson(json['cancel'] as Map<String, dynamic>),
);

Map<String, dynamic> _$BrainRequestToJson(BrainRequest instance) =>
    <String, dynamic>{
      'type': _$BrainRequestTypeEnumMap[instance.type]!,
      'init': instance.init?.toJson(),
      'runTurn': instance.runTurn?.toJson(),
      'toolResult': instance.toolResult?.toJson(),
      'cancel': instance.cancel?.toJson(),
    };

const _$BrainRequestTypeEnumMap = {
  BrainRequestType.init: 'init',
  BrainRequestType.runTurn: 'run_turn',
  BrainRequestType.toolResult: 'tool_result',
  BrainRequestType.cancel: 'cancel',
  BrainRequestType.reset: 'reset',
  BrainRequestType.dispose: 'dispose',
};

AgentReady _$AgentReadyFromJson(Map<String, dynamic> json) => AgentReady(
  type:
      $enumDecodeNullable(_$AgentEventTypeEnumMap, json['type']) ??
      AgentEventType.ready,
);

Map<String, dynamic> _$AgentReadyToJson(AgentReady instance) =>
    <String, dynamic>{'type': _$AgentEventTypeEnumMap[instance.type]!};

const _$AgentEventTypeEnumMap = {
  AgentEventType.ready: 'ready',
  AgentEventType.stepStarted: 'step_started',
  AgentEventType.contextTrimmed: 'context_trimmed',
  AgentEventType.telemetryUpdate: 'telemetry_update',
  AgentEventType.textDelta: 'text_delta',
  AgentEventType.reasoningDelta: 'reasoning_delta',
  AgentEventType.toolCalls: 'tool_calls',
  AgentEventType.toolResult: 'tool_result',
  AgentEventType.stepFinished: 'step_finished',
  AgentEventType.turnFinished: 'turn_finished',
  AgentEventType.error: 'error',
};

AgentStepStarted _$AgentStepStartedFromJson(Map<String, dynamic> json) =>
    AgentStepStarted(
      turnId: json['turnId'] as String,
      step: (json['step'] as num).toInt(),
      type:
          $enumDecodeNullable(_$AgentEventTypeEnumMap, json['type']) ??
          AgentEventType.stepStarted,
    );

Map<String, dynamic> _$AgentStepStartedToJson(AgentStepStarted instance) =>
    <String, dynamic>{
      'type': _$AgentEventTypeEnumMap[instance.type]!,
      'turnId': instance.turnId,
      'step': instance.step,
    };

AgentContextTrimmed _$AgentContextTrimmedFromJson(Map<String, dynamic> json) =>
    AgentContextTrimmed(
      turnId: json['turnId'] as String,
      step: (json['step'] as num).toInt(),
      droppedMessageCount: (json['droppedMessageCount'] as num).toInt(),
      type:
          $enumDecodeNullable(_$AgentEventTypeEnumMap, json['type']) ??
          AgentEventType.contextTrimmed,
    );

Map<String, dynamic> _$AgentContextTrimmedToJson(
  AgentContextTrimmed instance,
) => <String, dynamic>{
  'type': _$AgentEventTypeEnumMap[instance.type]!,
  'turnId': instance.turnId,
  'step': instance.step,
  'droppedMessageCount': instance.droppedMessageCount,
};

AgentTelemetryUpdate _$AgentTelemetryUpdateFromJson(
  Map<String, dynamic> json,
) => AgentTelemetryUpdate(
  turnId: json['turnId'] as String,
  step: (json['step'] as num).toInt(),
  promptTokens: (json['promptTokens'] as num).toInt(),
  budgetTokens: (json['budgetTokens'] as num).toInt(),
  remainingTokens: (json['remainingTokens'] as num).toInt(),
  contextSize: (json['contextSize'] as num).toInt(),
  maxOutputTokens: (json['maxOutputTokens'] as num).toInt(),
  safetyMarginTokens: (json['safetyMarginTokens'] as num).toInt(),
  type:
      $enumDecodeNullable(_$AgentEventTypeEnumMap, json['type']) ??
      AgentEventType.telemetryUpdate,
);

Map<String, dynamic> _$AgentTelemetryUpdateToJson(
  AgentTelemetryUpdate instance,
) => <String, dynamic>{
  'type': _$AgentEventTypeEnumMap[instance.type]!,
  'turnId': instance.turnId,
  'step': instance.step,
  'promptTokens': instance.promptTokens,
  'budgetTokens': instance.budgetTokens,
  'remainingTokens': instance.remainingTokens,
  'contextSize': instance.contextSize,
  'maxOutputTokens': instance.maxOutputTokens,
  'safetyMarginTokens': instance.safetyMarginTokens,
};

AgentTextDelta _$AgentTextDeltaFromJson(Map<String, dynamic> json) =>
    AgentTextDelta(
      turnId: json['turnId'] as String,
      step: (json['step'] as num).toInt(),
      text: json['text'] as String,
      type:
          $enumDecodeNullable(_$AgentEventTypeEnumMap, json['type']) ??
          AgentEventType.textDelta,
    );

Map<String, dynamic> _$AgentTextDeltaToJson(AgentTextDelta instance) =>
    <String, dynamic>{
      'type': _$AgentEventTypeEnumMap[instance.type]!,
      'turnId': instance.turnId,
      'step': instance.step,
      'text': instance.text,
    };

AgentReasoningDelta _$AgentReasoningDeltaFromJson(Map<String, dynamic> json) =>
    AgentReasoningDelta(
      turnId: json['turnId'] as String,
      step: (json['step'] as num).toInt(),
      text: json['text'] as String,
      type:
          $enumDecodeNullable(_$AgentEventTypeEnumMap, json['type']) ??
          AgentEventType.reasoningDelta,
    );

Map<String, dynamic> _$AgentReasoningDeltaToJson(
  AgentReasoningDelta instance,
) => <String, dynamic>{
  'type': _$AgentEventTypeEnumMap[instance.type]!,
  'turnId': instance.turnId,
  'step': instance.step,
  'text': instance.text,
};

AgentToolCalls _$AgentToolCallsFromJson(Map<String, dynamic> json) =>
    AgentToolCalls(
      turnId: json['turnId'] as String,
      step: (json['step'] as num).toInt(),
      calls: (json['calls'] as List<dynamic>)
          .map((e) => ToolCall.fromJson(e as Map<String, dynamic>))
          .toList(),
      finishReason: $enumDecode(_$FinishReasonEnumMap, json['finishReason']),
      preToolText: json['preToolText'] as String?,
      preToolReasoning: json['preToolReasoning'] as String?,
      type:
          $enumDecodeNullable(_$AgentEventTypeEnumMap, json['type']) ??
          AgentEventType.toolCalls,
    );

Map<String, dynamic> _$AgentToolCallsToJson(AgentToolCalls instance) =>
    <String, dynamic>{
      'type': _$AgentEventTypeEnumMap[instance.type]!,
      'turnId': instance.turnId,
      'step': instance.step,
      'calls': instance.calls.map((e) => e.toJson()).toList(),
      'finishReason': _$FinishReasonEnumMap[instance.finishReason]!,
      'preToolText': instance.preToolText,
      'preToolReasoning': instance.preToolReasoning,
    };

const _$FinishReasonEnumMap = {
  FinishReason.stop: 'stop',
  FinishReason.length: 'length',
  FinishReason.toolCalls: 'tool_calls',
  FinishReason.error: 'error',
  FinishReason.cancelled: 'cancelled',
  FinishReason.maxSteps: 'max_steps',
};

AgentToolResult _$AgentToolResultFromJson(Map<String, dynamic> json) =>
    AgentToolResult(
      turnId: json['turnId'] as String,
      step: (json['step'] as num).toInt(),
      result: ToolResult.fromJson(json['result'] as Map<String, dynamic>),
      type:
          $enumDecodeNullable(_$AgentEventTypeEnumMap, json['type']) ??
          AgentEventType.toolResult,
    );

Map<String, dynamic> _$AgentToolResultToJson(AgentToolResult instance) =>
    <String, dynamic>{
      'type': _$AgentEventTypeEnumMap[instance.type]!,
      'turnId': instance.turnId,
      'step': instance.step,
      'result': instance.result.toJson(),
    };

AgentStepFinished _$AgentStepFinishedFromJson(Map<String, dynamic> json) =>
    AgentStepFinished(
      turnId: json['turnId'] as String,
      step: (json['step'] as num).toInt(),
      text: json['text'] as String,
      finishReason: $enumDecode(_$FinishReasonEnumMap, json['finishReason']),
      reasoning: json['reasoning'] as String?,
      type:
          $enumDecodeNullable(_$AgentEventTypeEnumMap, json['type']) ??
          AgentEventType.stepFinished,
    );

Map<String, dynamic> _$AgentStepFinishedToJson(AgentStepFinished instance) =>
    <String, dynamic>{
      'type': _$AgentEventTypeEnumMap[instance.type]!,
      'turnId': instance.turnId,
      'step': instance.step,
      'text': instance.text,
      'finishReason': _$FinishReasonEnumMap[instance.finishReason]!,
      'reasoning': instance.reasoning,
    };

AgentTurnFinished _$AgentTurnFinishedFromJson(Map<String, dynamic> json) =>
    AgentTurnFinished(
      turnId: json['turnId'] as String,
      step: (json['step'] as num).toInt(),
      finishReason: $enumDecode(_$FinishReasonEnumMap, json['finishReason']),
      type:
          $enumDecodeNullable(_$AgentEventTypeEnumMap, json['type']) ??
          AgentEventType.turnFinished,
    );

Map<String, dynamic> _$AgentTurnFinishedToJson(AgentTurnFinished instance) =>
    <String, dynamic>{
      'type': _$AgentEventTypeEnumMap[instance.type]!,
      'turnId': instance.turnId,
      'step': instance.step,
      'finishReason': _$FinishReasonEnumMap[instance.finishReason]!,
    };

AgentError _$AgentErrorFromJson(Map<String, dynamic> json) => AgentError(
  error: json['error'] as String,
  turnId: json['turnId'] as String?,
  step: (json['step'] as num?)?.toInt(),
  type:
      $enumDecodeNullable(_$AgentEventTypeEnumMap, json['type']) ??
      AgentEventType.error,
);

Map<String, dynamic> _$AgentErrorToJson(AgentError instance) =>
    <String, dynamic>{
      'type': _$AgentEventTypeEnumMap[instance.type]!,
      'turnId': instance.turnId,
      'step': instance.step,
      'error': instance.error,
    };
