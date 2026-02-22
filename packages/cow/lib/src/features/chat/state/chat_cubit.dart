import 'dart:async';

import 'package:cow/src/app/app_model_profile.dart';
import 'package:cow/src/app/logic_bloc.dart';
import 'package:cow/src/app/session_log.dart';
import 'package:cow/src/features/chat/state/chat_data.dart';
import 'package:cow/src/features/chat/state/chat_input.dart';
import 'package:cow/src/features/chat/state/chat_logic.dart';
import 'package:cow/src/features/chat/state/chat_output.dart';
import 'package:cow/src/features/chat/state/models/brain_role.dart';
import 'package:cow/src/features/chat/state/models/chat_message.dart';
import 'package:cow/src/features/chat/state/summary/summary_brain.dart';
import 'package:cow/src/features/chat/state/summary/summary_input.dart';
import 'package:cow/src/features/chat/state/summary/summary_logic.dart';
import 'package:cow/src/features/chat/state/summary/summary_output.dart';
import 'package:cow/src/features/chat/state/tool_executor.dart';
import 'package:cow_brain/cow_brain.dart';
import 'package:logic_blocks/logic_blocks.dart';

class ChatCubit extends LogicBloc<ChatState> {
  ChatCubit({
    required ChatLogic logic,
    required this.toolRegistry,
    required this.primaryOptions,
    required this.modelProfile,
    required this.summaryOptions,
    required this.summaryModelProfile,
    required CowBrains<String> brains,
    required CowBrain primaryBrain,
    required SummaryBrain summaryBrain,
    required SummaryLogic summaryLogic,
    required ToolExecutor toolExecutor,
    required SessionLog sessionLog,
  }) : _brains = brains,
       _sessionLog = sessionLog,
       _primaryBrain = primaryBrain,
       _summaryBrain = summaryBrain,
       _summaryLogic = summaryLogic,
       _toolExecutor = toolExecutor,
       super(logic) {
    binding
      ..onOutput<StateUpdated>((_) => emit(state))
      ..onOutput<LoadModelsRequested>(
        (output) => unawaited(_loadModels()),
      )
      ..onOutput<InitializeBrainsRequested>(
        (output) => unawaited(_initializeBrains(output)),
      )
      ..onOutput<StartTurnRequested>((output) {
        _sessionLog
          ..userMessage(output.userMessage)
          ..turnStart();
        unawaited(_startTurn(output.userMessage, output.enableReasoning));
      })
      ..onOutput<AgentEventLog>(
        (output) => _sessionLog.logAgentEvent(output.event),
      )
      ..onOutput<TurnErrorLog>(
        (output) => _sessionLog.turnError(output.error),
      )
      ..onOutput<ExecuteToolCallsRequested>(
        (output) => unawaited(_executeToolCalls(output.turnId, output.event)),
      )
      ..onOutput<CancelSummaryRequested>(
        (_) => _summaryLogic.input(const CancelSummary()),
      )
      ..onOutput<ResetSummaryRequested>(
        (_) => _summaryLogic.input(const ResetSummary()),
      )
      ..onOutput<StartSummaryTurnRequested>(
        (output) => _summaryLogic.input(StartTurn(output.responseId)),
      )
      ..onOutput<SummarizeUserMessageRequested>((output) {
        _summaryLogic.input(
          SummarizeUserMessage(
            output.text,
            enableReasoning: output.enableReasoning,
          ),
        );
      })
      ..onOutput<ReasoningSummaryRequested>((output) {
        _summaryLogic.input(ReasoningDelta(output.text));
      })
      ..onOutput<FreezeSummaryRequested>((output) {
        _summaryLogic.input(const Freeze());
      });

    _summaryBinding = _summaryLogic.bind()
      ..onOutput<RunSummaryRequested>(
        (output) => unawaited(_runSummary(output)),
      )
      ..onOutput<SummaryChanged>((_) => emit(state));

    _summaryLogic.start();
  }

  static const String primaryBrainKey = 'primary';
  static const String lightweightBrainKey = 'lightweight';

  final ToolRegistry toolRegistry;
  final BackendRuntimeOptions primaryOptions;
  final AppModelProfile modelProfile;
  final BackendRuntimeOptions summaryOptions;
  final AppModelProfile summaryModelProfile;

  final CowBrains<String> _brains;
  final CowBrain _primaryBrain;
  final SessionLog _sessionLog;
  final SummaryBrain _summaryBrain;
  final SummaryLogic _summaryLogic;
  final ToolExecutor _toolExecutor;

  late final LogicBlockBinding<SummaryState> _summaryBinding;

  var _responseCounter = 0;

  void toggleReasoning() => input(const ToggleReasoning());

  void initialize({List<ChatMessage> existingMessages = const []}) {
    input(
      Start(
        existingMessages: [...existingMessages],
      ),
    );
  }

  void submit(String message) {
    input(Submit(message.trim(), responseId: _nextResponseId()));
  }

  void cancel() => input(const Cancel());

  void clear() => input(const Clear());

  void reset() => input(const Reset());

  @override
  Future<void> close() async {
    if (isClosed) return;

    input(const Dispose());
    _summaryLogic.input(const CancelSummary());
    _summaryBinding.dispose();
    _summaryLogic.stop();
    await _brains.remove(primaryBrainKey);
    await _brains.remove(lightweightBrainKey);
    return super.close();
  }

  Future<void> _loadModels() async {
    try {
      final modelConfigs = [
        (
          BrainRole.primary,
          primaryOptions.modelPath,
          modelProfile.downloadableModel.id,
          primaryOptions.backend,
          primaryOptions.libraryPath,
        ),
        (
          BrainRole.summary,
          summaryOptions.modelPath,
          summaryModelProfile.downloadableModel.id,
          summaryOptions.backend,
          summaryOptions.libraryPath,
        ),
      ];

      // Tell logic block how many models we're loading.
      input(SetTotalModels(modelConfigs.length));

      for (var i = 0; i < modelConfigs.length; i++) {
        final (role, path, name, backend, mlxLibPath) = modelConfigs[i];
        final model = await _brains.loadModel(
          modelPath: path,
          backend: backend,
          libraryPathOverride: mlxLibPath,
          onProgress: (progress) {
            input(
              ModelLoadProgressUpdate(
                currentModel: i + 1,
                totalModels: modelConfigs.length,
                progress: progress,
                modelName: name,
              ),
            );
            return true;
          },
        );
        input(ModelLoaded(role: role, model: model));
      }
      // Logic block will output InitializeBrainsRequested when all loaded.
    } on Object catch (e) {
      _sessionLog.turnError('model load failed: $e');
      input(ModelsLoadFailed(e.toString()));
    }
  }

  Future<void> _initializeBrains(InitializeBrainsRequested request) async {
    try {
      const agentSettings = AgentSettings(
        safetyMarginTokens: 64,
        maxSteps: 8,
      );

      final primaryModel = request.models[BrainRole.primary]!;
      final summaryModel = request.models[BrainRole.summary]!;

      await _primaryBrain.init(
        modelHandle: primaryModel.modelPointer,
        options: primaryOptions,
        profile: modelProfile.modelFamily,
        tools: toolRegistry.definitions,
        settings: agentSettings,
        enableReasoning: request.enableReasoning,
      );

      await _summaryBrain.init(
        modelHandle: summaryModel.modelPointer,
        options: summaryOptions,
        profile: summaryModelProfile.modelFamily,
      );

      input(const BrainsInitialized(settings: agentSettings));
    } on Object catch (e) {
      input(ModelsLoadFailed(e.toString()));
    }
  }

  Future<void> _startTurn(String userMessage, bool enableReasoning) async {
    try {
      await for (final event in _primaryBrain.runTurn(
        userMessage: Message(role: Role.user, content: userMessage),
        settings: get<ChatData>().agentSettings,
        enableReasoning: enableReasoning,
      )) {
        input(AgentEventReceived(event));
      }

      input(const TurnFinalized());
    } on Object catch (e) {
      input(TurnError(e.toString()));
    }
  }

  Future<void> _executeToolCalls(String turnId, AgentToolCalls event) async {
    try {
      await _toolExecutor.execute(turnId: turnId, calls: event.calls);
    } finally {
      input(const ToolCallsComplete());
    }
  }

  int _nextResponseId() => _responseCounter++;

  Future<void> _runSummary(RunSummaryRequested output) async {
    try {
      final summary = await _summaryBrain.generateSummary(
        output.text,
        output.prompt,
      );
      _summaryLogic.input(
        SummaryComplete(summary, requestId: output.requestId),
      );
    } on Object catch (e) {
      _summaryLogic.input(SummaryFailed(e, requestId: output.requestId));
    }
  }
}
