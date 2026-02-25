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
    required this.defaultSettings,
    required this.options,
    required this.enableReasoningDefault,
    required this.systemPrompt,
    required AgentRunner agent,
    required Conversation conversation,
  }) {
    agents[0] = agent;
    conversations[0] = conversation;
  }

  final BrainRuntime runtime;
  final AgentSettings defaultSettings;
  final BackendRuntimeOptions options;
  final bool enableReasoningDefault;
  final String systemPrompt;

  // Per-sequence state.
  final Map<int, AgentRunner> agents = {};
  final Map<int, Conversation> conversations = {};
}

/// Turn-level coordination. Always exists on blackboard.
final class BrainIsolateData {
  final Set<int> activeSequences = {};

  // Per-sequence turn settings (set when turn starts, used by _streamTurn).
  final Map<int, bool> cancelRequested = {0: false};
  final Map<int, int> maxSteps = {0: 8};
  final Map<int, bool> enableReasoning = {0: true};
}
