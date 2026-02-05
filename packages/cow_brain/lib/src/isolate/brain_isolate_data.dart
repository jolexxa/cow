// Internal data containers for brain isolate state machine.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/agent/agent_runner.dart';
import 'package:cow_brain/src/core/conversation.dart';
import 'package:cow_brain/src/isolate/brain_isolate.dart';
import 'package:cow_brain/src/isolate/models.dart';

/// Created during init, stored on blackboard. Non-nullable because it only
/// exists after successful initialization.
final class BrainIsolateConfig {
  BrainIsolateConfig({
    required this.runtime,
    required this.agent,
    required this.conversation,
    required this.defaultSettings,
    required this.runtimeOptions,
    required this.enableReasoningDefault,
  });

  final BrainRuntime runtime;
  final AgentSettings defaultSettings;
  final LlamaRuntimeOptions runtimeOptions;
  final bool enableReasoningDefault;

  // Mutable — agent settings change per-turn, conversation resets
  AgentRunner agent;
  Conversation conversation;
}

/// Turn-level coordination. Always exists on blackboard.
final class BrainIsolateData {
  bool cancelRequested = false;

  // Turn settings (set when turn starts, used by _streamTurn)
  int maxSteps = 8;
  bool enableReasoning = true;
}
