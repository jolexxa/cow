// Isolate entrypoint and session for running the brain runtime.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:isolate';

import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:cow_brain/src/adapters/mlx/mlx.dart';
import 'package:cow_brain/src/agent/agent_runner.dart';
import 'package:cow_brain/src/agent/agent_setup.dart';
import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/core/conversation.dart';
import 'package:cow_brain/src/core/llm_adapter.dart';
import 'package:cow_brain/src/core/model_output.dart';
import 'package:cow_brain/src/isolate/brain_isolate_data.dart';
import 'package:cow_brain/src/isolate/brain_isolate_input.dart';
import 'package:cow_brain/src/isolate/brain_isolate_logic.dart';
import 'package:cow_brain/src/isolate/brain_isolate_output.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/tools/tool_registry.dart';
import 'package:logic_blocks/logic_blocks.dart';

typedef BrainIsolateEntry = void Function(SendPort);
typedef AgentBundle = ({
  AgentRunner agent,
  Conversation conversation,
  LlmAdapter llm,
  ToolRegistry tools,
  ContextManager context,
  BrainRuntime runtime,
});
typedef AgentBundleFactory =
    AgentBundle Function({
      required int modelPointer,
      required BackendRuntimeOptions options,
      required ModelProfileId profile,
      required ToolRegistry tools,
      required Conversation conversation,
      required int contextSize,
      required int maxOutputTokens,
      required double temperature,
      required int safetyMarginTokens,
    });

// Test hooks to override the runtime factory without loading native libraries.
LlamaClientApi? brainRuntimeClientOverride;
LlamaBindings? brainRuntimeBindingsOverride;
MlxClientApi? brainMlxRuntimeClientOverride;
MlxBindings? brainMlxRuntimeBindingsOverride;

BrainRuntime Function({
  required int modelPointer,
  required BackendRuntimeOptions options,
})
brainRuntimeFactory = _createRuntime;

BrainRuntime _createRuntime({
  required int modelPointer,
  required BackendRuntimeOptions options,
}) {
  switch (options) {
    case LlamaCppRuntimeOptions():
      final libraryPath = options.libraryPath;
      return LlamaCppRuntime(
        modelPointer: modelPointer,
        options: options,
        // coverage:ignore-start
        client:
            brainRuntimeClientOverride ?? LlamaClient(libraryPath: libraryPath),
        bindings:
            brainRuntimeBindingsOverride ??
            LlamaClient.openBindings(libraryPath: libraryPath),
        // coverage:ignore-end
      );
    case MlxRuntimeOptions():
      final libraryPath = options.libraryPath;
      return MlxRuntime(
        modelId: modelPointer,
        options: options,
        // coverage:ignore-start
        client:
            brainMlxRuntimeClientOverride ??
            MlxClient(libraryPath: libraryPath),
        bindings:
            brainMlxRuntimeBindingsOverride ??
            MlxBindingsLoader.open(libraryPath: libraryPath),
        // coverage:ignore-end
      );
  }
}

abstract interface class BrainRuntime {
  void reset();
  void dispose();
}

void brainIsolateEntry(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);
  final session = _BrainIsolate(sendPort);
  receivePort.listen(session.handleMessage);
}

AgentBundle _createDefaultBundle({
  required int modelPointer,
  required BackendRuntimeOptions options,
  required ModelProfileId profile,
  required ToolRegistry tools,
  required Conversation conversation,
  required int contextSize,
  required int maxOutputTokens,
  required double temperature,
  required int safetyMarginTokens,
}) {
  final bundle = createAgent(
    modelPointer: modelPointer,
    options: options,
    profileId: profile,
    tools: tools,
    conversation: conversation,
    contextSize: contextSize,
    maxOutputTokens: maxOutputTokens,
    temperature: temperature,
    safetyMarginTokens: safetyMarginTokens,
    runtimeFactory: brainRuntimeFactory,
  );
  return (
    agent: bundle.agent,
    conversation: bundle.conversation,
    llm: bundle.llm,
    tools: bundle.tools,
    context: bundle.context,
    runtime: bundle.runtime,
  );
}

final class _BrainIsolate {
  _BrainIsolate(
    this._out, {
    AgentBundleFactory? bundleFactory,
  }) : _logic = BrainIsolateLogic(
         bundleFactory: bundleFactory ?? _createDefaultBundle,
       ) {
    _binding = _logic.bind();
    _setupBindings();
    _logic.start();
  }

  final SendPort _out;
  final BrainIsolateLogic _logic;
  late final LogicBlockBinding<BrainIsolateState> _binding;

  /// Interrupt handle for cancelling tool waits. Only non-null while
  /// [_executeToolCalls] is blocked waiting for results.
  Completer<void>? _toolWaitInterrupt;

  /// Pending tool result completers, keyed by tool call ID.
  final Map<String, Completer<ToolResult>> _pendingToolResults = {};

  BrainIsolateData get _data => _logic.get<BrainIsolateData>();
  BrainIsolateConfig get _config => _logic.get<BrainIsolateConfig>();

  void _setupBindings() {
    _binding
      ..onOutput<SendEventRequested>((output) => _sendEvent(output.event))
      ..onOutput<SendErrorRequested>((output) => _sendError(output.message))
      ..onOutput<StoreConfigRequested>(
        (output) => _logic.blackboard.overwrite(output.config),
      )
      ..onOutput<StreamTurnRequested>((_) => unawaited(_streamTurn()))
      ..onOutput<CancelTurnRequested>((_) => _cancelTurn())
      ..onOutput<DisposeRuntimeRequested>((_) => _disposeRuntime())
      ..onOutput<ResetRuntimeRequested>((_) => _resetRuntime())
      ..onOutput<CompleteToolResultRequested>(
        (output) => _completeToolResult(output.result),
      );
  }

  void handleMessage(Object? message) {
    if (message is! Map) return;
    final payload = Map<String, Object?>.from(message);
    final request = BrainRequest.fromJson(payload);
    switch (request.type) {
      case BrainRequestType.init:
        final init = request.init;
        if (init == null) {
          _sendError('Init payload was missing.');
          return;
        }
        _logic.input(InitInput(request: init));
      case BrainRequestType.runTurn:
        final runTurn = request.runTurn;
        if (runTurn == null) {
          _sendError('RunTurn payload was missing.');
          return;
        }
        _logic.input(RunTurnInput(request: runTurn));
      case BrainRequestType.toolResult:
        final toolResult = request.toolResult;
        if (toolResult == null) {
          _sendError('ToolResult payload was missing.');
          return;
        }
        _logic.input(ToolResultInput(result: toolResult.toolResult));
      case BrainRequestType.cancel:
        final cancel = request.cancel;
        if (cancel == null) {
          _sendError('Cancel payload was missing.');
          return;
        }
        _logic.input(const CancelInput());
      case BrainRequestType.reset:
        _logic.input(const ResetInput());
      case BrainRequestType.dispose:
        _logic.input(const DisposeInput());
    }
  }

  bool _shouldCancel() => _data.cancelRequested;

  Future<void> _streamTurn() async {
    try {
      await _config.agent
          .runTurn(
            _config.conversation,
            toolExecutor: _executeToolCalls,
            shouldCancel: _shouldCancel,
            maxSteps: _data.maxSteps,
            enableReasoning: _data.enableReasoning,
          )
          .forEach(_sendEvent);
      _logic.input(const TurnCompleted());
    } on Object catch (error) {
      _logic.input(TurnFailed(error: error.toString()));
    }
  }

  Future<List<ToolResult>> _executeToolCalls(List<ToolCall> calls) async {
    if (_shouldCancel()) throw const CancelledException();

    final interrupt = Completer<void>();
    _toolWaitInterrupt = interrupt;

    try {
      final futures = <Future<ToolResult>>[];
      for (final call in calls) {
        final completer = Completer<ToolResult>();
        _pendingToolResults[call.id] = completer;
        futures.add(completer.future);
      }

      final cancelFuture = interrupt.future.then<List<ToolResult>>(
        (_) => throw const CancelledException(),
      );

      return await Future.any<List<ToolResult>>([
        Future.wait(futures),
        cancelFuture,
      ]);
    } finally {
      _toolWaitInterrupt = null;
      for (final call in calls) {
        _pendingToolResults.remove(call.id);
      }
    }
  }

  void _cancelTurn() {
    _data.cancelRequested = true;
    final interrupt = _toolWaitInterrupt;
    if (interrupt != null && !interrupt.isCompleted) {
      interrupt.complete();
    }
  }

  void _completeToolResult(ToolResult result) {
    final completer = _pendingToolResults.remove(result.toolCallId);
    if (completer == null || completer.isCompleted) return;
    completer.complete(result);
  }

  void _resetRuntime() {
    _configOrNull?.runtime.reset();
  }

  void _disposeRuntime() {
    _configOrNull?.runtime.dispose();
  }

  BrainIsolateConfig? get _configOrNull =>
      _logic.blackboard.getOrNull<BrainIsolateConfig>();

  void _sendEvent(AgentEvent event) {
    _out.send(event.toJson());
  }

  void _sendError(String message) {
    _out.send(AgentError(error: message).toJson());
  }
}

/// Test-only harness for driving a brain session without spawning an isolate.
final class BrainIsolateTestHarness {
  BrainIsolateTestHarness(
    SendPort sendPort, {
    AgentBundleFactory? bundleFactory,
  }) : _session = _BrainIsolate(
         sendPort,
         bundleFactory: bundleFactory,
       );

  final _BrainIsolate _session;

  void handleMessage(Object? message) {
    _session.handleMessage(message);
  }
}
