// Integration helpers compose existing contracts; docs can follow.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/inference_adapter.dart';
import 'package:cow_brain/src/adapters/llama/llama_cpp_runtime.dart';
import 'package:cow_brain/src/adapters/model_profiles.dart';
import 'package:cow_brain/src/adapters/profile_detector.dart';
import 'package:cow_brain/src/adapters/prompt_formatter.dart';
import 'package:cow_brain/src/agent/agent_loop.dart';
import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/context/context_manager.dart';
import 'package:cow_brain/src/core/conversation.dart';
import 'package:cow_brain/src/isolate/brain_isolate.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/tools/tool_registry.dart';

({
  AgentLoop agent,
  Conversation conversation,
  InferenceAdapter llm,
  ToolRegistry tools,
  ContextManager context,
})
createAgentWithLlama({
  required InferenceRuntime runtime,
  required int contextSize,
  required int maxOutputTokens,
  required double temperature,
  required ModelProfile profile,
  required ToolRegistry tools,
  required Conversation conversation,
  required int safetyMarginTokens,
}) {
  final llm = InferenceAdapter(runtime: runtime, profile: profile);
  final toolRegistry = tools;
  final convo = conversation;
  final contextManager = SlidingWindowContextManager(
    counter: llm.tokenCounter,
    safetyMarginTokens: safetyMarginTokens,
  );

  final agent = AgentLoop(
    llm: llm,
    tools: toolRegistry,
    context: contextManager,
    contextSize: contextSize,
    maxOutputTokens: maxOutputTokens,
    temperature: temperature,
  );

  return (
    agent: agent,
    conversation: convo,
    llm: llm,
    tools: toolRegistry,
    context: contextManager,
  );
}

({
  AgentLoop agent,
  Conversation conversation,
  InferenceAdapter llm,
  ToolRegistry tools,
  ContextManager context,
  BrainRuntime runtime,
})
createAgent({
  required int modelPointer,
  required BackendRuntimeOptions options,
  required ToolRegistry tools,
  required Conversation conversation,
  required ModelProfileId profileId,
  required int contextSize,
  required int maxOutputTokens,
  required double temperature,
  required int safetyMarginTokens,
  required BrainRuntime Function({
    required int modelPointer,
    required BackendRuntimeOptions options,
  })
  runtimeFactory,
}) {
  final runtime = runtimeFactory(
    modelPointer: modelPointer,
    options: options,
  );

  // Profile detection: only auto-detect from chat template for llama.cpp
  // (MLX models don't have GGUF metadata). For MLX, require explicit profile.
  ModelProfile profile;
  if (profileId == ModelProfileId.auto && runtime is LlamaCppRuntime) {
    profile = detectProfileFromRuntime(
      runtime,
      fallback: ModelProfiles.qwen3,
    );
  } else {
    profile = ModelProfiles.profileFor(
      profileId == ModelProfileId.auto ? ModelProfileId.qwen3 : profileId,
    );
  }

  // Validate context size against the backend's configured size.
  if (contextSize > options.contextSize) {
    throw ArgumentError.value(
      contextSize,
      'contextSize',
      'must be <= configured context size (${options.contextSize})',
    );
  }

  // Both LlamaCppRuntime and MlxRuntime implement InferenceRuntime.
  final llamaRuntime = runtime as InferenceRuntime;
  final bundle = createAgentWithLlama(
    runtime: llamaRuntime,
    tools: tools,
    conversation: conversation,
    contextSize: contextSize,
    maxOutputTokens: maxOutputTokens,
    temperature: temperature,
    profile: profile,
    safetyMarginTokens: safetyMarginTokens,
  );

  return (
    agent: bundle.agent,
    conversation: bundle.conversation,
    llm: bundle.llm,
    tools: bundle.tools,
    context: bundle.context,
    runtime: runtime,
  );
}

/// Detects the appropriate profile from a runtime's chat template.
///
/// Returns the detected profile, or [fallback] if the chat template is
/// unavailable or unrecognized.
ModelProfile detectProfileFromRuntime(
  LlamaCppRuntime runtime, {
  required ModelProfile fallback,
}) {
  final template = runtime.chatTemplate;
  if (template == null) return fallback;
  return const ProfileDetector().detect(template) ?? fallback;
}
