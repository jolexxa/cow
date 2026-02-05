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

    final contextSize = request.runtimeOptions.contextOptions.contextSize;
    final maxOutputTokens = request.runtimeOptions.maxOutputTokensDefault;
    final temperature =
        request.runtimeOptions.samplingOptions.temperature ?? 0.7;

    final tools = ToolRegistry();
    for (final tool in request.tools) {
      tools.register(
        tool,
        (_) => throw StateError('Tool execution is handled by the client.'),
      );
    }

    final bundle = factory(
      modelPointer: request.modelPointer,
      runtimeOptions: request.runtimeOptions,
      profile: request.profile,
      tools: tools,
      conversation: Conversation.initial(),
      contextSize: contextSize,
      maxOutputTokens: maxOutputTokens,
      temperature: temperature,
      safetyMarginTokens: request.settings.safetyMarginTokens,
    );

    return BrainIsolateConfig(
      runtime: bundle.runtime,
      agent: bundle.agent,
      conversation: bundle.conversation,
      defaultSettings: request.settings,
      runtimeOptions: request.runtimeOptions,
      enableReasoningDefault: request.enableReasoning,
    );
  }
}

final class UninitializedState extends BrainIsolateState {
  UninitializedState() {
    on<InitInput>((input) {
      final config = createConfig(input.request);

      data
        ..maxSteps = config.defaultSettings.maxSteps
        ..enableReasoning = config.enableReasoningDefault;

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
  }
}

final class IdleState extends BrainIsolateState {
  IdleState() {
    on<InitInput>((input) {
      output(const DisposeRuntimeRequested());

      final newConfig = createConfig(input.request);

      data
        ..maxSteps = newConfig.defaultSettings.maxSteps
        ..enableReasoning = newConfig.enableReasoningDefault;

      output(StoreConfigRequested(config: newConfig));
      output(const SendEventRequested(event: AgentReady()));
      return toSelf();
    });

    on<RunTurnInput>((input) {
      final request = input.request;
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
        ..cancelRequested = false
        ..maxSteps = request.settings.maxSteps
        ..enableReasoning = request.enableReasoning;

      config.conversation.addUser(userMessage.content, name: userMessage.name);

      output(const StreamTurnRequested());
      return to<TurnActiveState>();
    });

    on<ToolResultInput>((_) => toSelf());
    on<CancelInput>((_) => toSelf());

    on<ResetInput>((_) {
      data
        ..cancelRequested = true
        ..maxSteps = config.defaultSettings.maxSteps
        ..enableReasoning = config.enableReasoningDefault;

      config.conversation = Conversation.initial();

      output(const ResetRuntimeRequested());
      return toSelf();
    });

    on<DisposeInput>((_) {
      output(const DisposeRuntimeRequested());
      return to<DisposedState>();
    });

    on<TurnCompleted>((_) => toSelf());
    on<TurnFailed>((_) => toSelf());
  }
}

final class TurnActiveState extends BrainIsolateState {
  TurnActiveState() {
    on<InitInput>((_) {
      output(const SendErrorRequested(message: 'Turn already running.'));
      return toSelf();
    });

    on<RunTurnInput>((_) {
      output(const SendErrorRequested(message: 'Turn already running.'));
      return toSelf();
    });

    on<ToolResultInput>((input) {
      output(CompleteToolResultRequested(result: input.result));
      return toSelf();
    });

    on<CancelInput>((_) {
      output(const CancelTurnRequested());
      return toSelf();
    });

    on<ResetInput>((_) {
      output(const CancelTurnRequested());
      return toSelf();
    });

    on<DisposeInput>((_) {
      output(const CancelTurnRequested());
      output(const DisposeRuntimeRequested());
      return to<DisposedState>();
    });

    on<TurnCompleted>((_) => to<IdleState>());

    on<TurnFailed>((input) {
      output(SendErrorRequested(message: input.error));
      return to<IdleState>();
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
