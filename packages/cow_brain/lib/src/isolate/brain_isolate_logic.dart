// Brain isolate state machine using logic_blocks.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/core/conversation.dart';
import 'package:cow_brain/src/isolate/brain_isolate.dart';
import 'package:cow_brain/src/isolate/brain_isolate_data.dart';
import 'package:cow_brain/src/isolate/brain_isolate_input.dart';
import 'package:cow_brain/src/isolate/brain_isolate_output.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/tools/tool_registry.dart';
import 'package:logic_blocks/logic_blocks.dart';

sealed class BrainIsolateState extends StateLogic<BrainIsolateState> {
  BrainIsolateData get data => get<BrainIsolateData>();
  BrainIsolateConfig get config => get<BrainIsolateConfig>();

  BrainIsolateConfig createConfig(InitRequest request) {
    final factory = get<AgentBundleFactory>();
    final options = request.options;

    final tools = ToolRegistry();
    for (final tool in request.tools) {
      tools.register(
        tool,
        (_) => throw StateError('Tool execution is handled by the client.'),
      );
    }

    final bundle = factory(
      modelPointer: request.modelHandle,
      options: options,
      profile: request.profile,
      tools: tools,
      conversation: Conversation.initial(),
      contextSize: options.contextSize,
      maxOutputTokens: options.maxOutputTokensDefault,
      temperature: options.samplingOptions.temperature ?? 0.7,
      safetyMarginTokens: request.settings.safetyMarginTokens,
    );

    return BrainIsolateConfig(
      runtime: bundle.runtime,
      agent: bundle.agent,
      conversation: bundle.conversation,
      defaultSettings: request.settings,
      options: options,
      enableReasoningDefault: request.enableReasoning,
    );
  }
}

final class UninitializedState extends BrainIsolateState {
  UninitializedState() {
    on<InitInput>((input) {
      final config = createConfig(input.request);

      data
        ..maxSteps[0] = config.defaultSettings.maxSteps
        ..enableReasoning[0] = config.enableReasoningDefault;

      output(StoreConfigRequested(config: config));
      output(const SendEventRequested(event: AgentReady()));
      return to<IdleState>();
    });

    on<RunTurnInput>((_) {
      output(const SendErrorRequested(message: 'Brain is not initialized.'));
      return toSelf();
    });

    on<ToolResultInput>((_) => toSelf());
    on<CancelInput>((_) => toSelf());
    on<ResetInput>((_) {
      output(const SendErrorRequested(message: 'Brain is not initialized.'));
      return toSelf();
    });
    on<DisposeInput>((_) => to<DisposedState>());
    on<TurnCompleted>((_) => toSelf());
    on<TurnFailed>((_) => toSelf());
    on<CreateSequenceInput>((_) {
      output(const SendErrorRequested(message: 'Brain is not initialized.'));
      return toSelf();
    });
    on<DestroySequenceInput>((_) {
      output(const SendErrorRequested(message: 'Brain is not initialized.'));
      return toSelf();
    });
  }
}

final class IdleState extends BrainIsolateState {
  IdleState() {
    on<InitInput>((input) {
      output(const DisposeRuntimeRequested());

      final newConfig = createConfig(input.request);

      data
        ..maxSteps[0] = newConfig.defaultSettings.maxSteps
        ..enableReasoning[0] = newConfig.enableReasoningDefault;

      output(StoreConfigRequested(config: newConfig));
      output(const SendEventRequested(event: AgentReady()));
      return toSelf();
    });

    on<RunTurnInput>((input) {
      final request = input.request;
      final userMessage = request.userMessage;
      final seqId = request.sequenceId;

      if (userMessage.role != Role.user) {
        output(
          const SendErrorRequested(
            message: 'run_turn requires a user message.',
          ),
        );
        return toSelf();
      }

      data
        ..cancelRequested[seqId] = false
        ..maxSteps[seqId] = request.settings.maxSteps
        ..enableReasoning[seqId] = request.enableReasoning
        ..activeSequences.add(seqId);

      config.conversations[seqId]?.addUser(
        userMessage.content,
        name: userMessage.name,
      );

      output(StreamTurnRequested(sequenceId: seqId));
      return to<TurnActiveState>();
    });

    on<ToolResultInput>((_) => toSelf());
    on<CancelInput>((_) => toSelf());

    on<ResetInput>((_) {
      data
        ..cancelRequested.clear()
        ..cancelRequested[0] = false
        ..maxSteps.clear()
        ..maxSteps[0] = config.defaultSettings.maxSteps
        ..enableReasoning.clear()
        ..enableReasoning[0] = config.enableReasoningDefault;

      // Reset all conversations to just sequence 0.
      config.conversations.clear();
      config.conversations[0] = Conversation.initial();
      config.agents.removeWhere((k, _) => k != 0);

      output(const ResetRuntimeRequested());
      return toSelf();
    });

    on<DisposeInput>((_) {
      output(const DisposeRuntimeRequested());
      return to<DisposedState>();
    });

    on<TurnCompleted>((_) => toSelf());
    on<TurnFailed>((_) => toSelf());

    on<CreateSequenceInput>((input) {
      output(CreateSequenceRequested(request: input.request));
      return toSelf();
    });

    on<DestroySequenceInput>((input) {
      output(DestroySequenceRequested(request: input.request));
      return toSelf();
    });
  }
}

final class TurnActiveState extends BrainIsolateState {
  TurnActiveState() {
    on<InitInput>((_) {
      output(const SendErrorRequested(message: 'Turn already running.'));
      return toSelf();
    });

    on<RunTurnInput>((input) {
      final request = input.request;
      final seqId = request.sequenceId;

      // Allow concurrent turns on different sequences.
      if (data.activeSequences.contains(seqId)) {
        output(
          SendErrorRequested(
            message: 'Turn already running on sequence $seqId.',
          ),
        );
        return toSelf();
      }

      final userMessage = request.userMessage;
      if (userMessage.role != Role.user) {
        output(
          const SendErrorRequested(
            message: 'run_turn requires a user message.',
          ),
        );
        return toSelf();
      }

      data
        ..cancelRequested[seqId] = false
        ..maxSteps[seqId] = request.settings.maxSteps
        ..enableReasoning[seqId] = request.enableReasoning
        ..activeSequences.add(seqId);

      config.conversations[seqId]?.addUser(
        userMessage.content,
        name: userMessage.name,
      );

      output(StreamTurnRequested(sequenceId: seqId));
      return toSelf();
    });

    on<ToolResultInput>((input) {
      output(CompleteToolResultRequested(result: input.result));
      return toSelf();
    });

    on<CancelInput>((input) {
      output(CancelTurnRequested(sequenceId: input.sequenceId));
      return toSelf();
    });

    on<ResetInput>((_) {
      // Cancel all active turns.
      for (final seqId in data.activeSequences) {
        output(CancelTurnRequested(sequenceId: seqId));
      }
      return toSelf();
    });

    on<DisposeInput>((_) {
      for (final seqId in data.activeSequences) {
        output(CancelTurnRequested(sequenceId: seqId));
      }
      output(const DisposeRuntimeRequested());
      return to<DisposedState>();
    });

    on<TurnCompleted>((input) {
      data.activeSequences.remove(input.sequenceId);
      if (data.activeSequences.isEmpty) {
        return to<IdleState>();
      }
      return toSelf();
    });

    on<TurnFailed>((input) {
      data.activeSequences.remove(input.sequenceId);
      output(SendErrorRequested(message: input.error));
      if (data.activeSequences.isEmpty) {
        return to<IdleState>();
      }
      return toSelf();
    });

    on<CreateSequenceInput>((input) {
      output(CreateSequenceRequested(request: input.request));
      return toSelf();
    });

    on<DestroySequenceInput>((input) {
      final seqId = input.request.sequenceId;
      if (data.activeSequences.contains(seqId)) {
        output(
          SendErrorRequested(
            message: 'Cannot destroy sequence $seqId while turn is active.',
          ),
        );
        return toSelf();
      }
      output(DestroySequenceRequested(request: input.request));
      return toSelf();
    });
  }
}

final class DisposedState extends BrainIsolateState {
  DisposedState() {
    on<InitInput>((_) => toSelf());
    on<RunTurnInput>((_) => toSelf());
    on<ToolResultInput>((_) => toSelf());
    on<CancelInput>((_) => toSelf());
    on<ResetInput>((_) => toSelf());
    on<DisposeInput>((_) => toSelf());
    on<TurnCompleted>((_) => toSelf());
    on<TurnFailed>((_) => toSelf());
    on<CreateSequenceInput>((_) => toSelf());
    on<DestroySequenceInput>((_) => toSelf());
  }
}

final class BrainIsolateLogic extends LogicBlock<BrainIsolateState> {
  BrainIsolateLogic({required AgentBundleFactory bundleFactory}) {
    set(BrainIsolateData());
    set(bundleFactory);
    set(UninitializedState());
    set(IdleState());
    set(TurnActiveState());
    set(DisposedState());
  }

  @override
  Transition getInitialState() => to<UninitializedState>();
}
