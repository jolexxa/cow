// Integration helpers compose existing contracts; docs can follow.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/llama/llama_adapter.dart';
import 'package:cow_brain/src/adapters/llama/llama_cpp_runtime.dart';
import 'package:cow_brain/src/adapters/llama/llama_prompt_formatter.dart';
import 'package:cow_brain/src/agent/agent_loop.dart';
import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/context/context_manager.dart';
import 'package:cow_brain/src/core/conversation.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/tools/tool_registry.dart';

({
  AgentLoop agent,
  Conversation conversation,
  LlamaAdapter llm,
  ToolRegistry tools,
  ContextManager context,
})
createAgentWithLlama({
  required LlamaRuntime runtime,
  required int contextSize,
  required int maxOutputTokens,
  required double temperature,
  required LlamaModelProfile profile,
  required ToolRegistry tools,
  required Conversation conversation,
  required int safetyMarginTokens,
  required int maxSteps,
}) {
  final llm = LlamaAdapter(runtime: runtime, profile: profile);
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
    maxSteps: maxSteps,
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
  LlamaAdapter llm,
  ToolRegistry tools,
  ContextManager context,
  LlamaCppRuntime runtime,
})
createQwenAgent({
  required LlamaRuntimeOptions runtimeOptions,
  required ToolRegistry tools,
  required Conversation conversation,
  required LlamaModelProfile profile,
  required int contextSize,
  required int maxOutputTokens,
  required double temperature,
  required int safetyMarginTokens,
  required int maxSteps,
  required LlamaCppRuntime Function(LlamaRuntimeOptions options) runtimeFactory,
}) {
  final runtime = runtimeFactory(runtimeOptions);

  if (contextSize > runtimeOptions.contextOptions.contextSize) {
    throw ArgumentError.value(
      contextSize,
      'contextSize',
      'must be <= runtimeOptions.contextOptions.contextSize '
          '(${runtimeOptions.contextOptions.contextSize})',
    );
  }

  final bundle = createAgentWithLlama(
    runtime: runtime,
    tools: tools,
    conversation: conversation,
    contextSize: contextSize,
    maxOutputTokens: maxOutputTokens,
    temperature: temperature,
    profile: profile,
    safetyMarginTokens: safetyMarginTokens,
    maxSteps: maxSteps,
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
