// Isolate entrypoint and session for running the brain runtime.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:isolate';

import 'package:cow_brain/src/adapters/inference_adapter.dart';
import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:cow_brain/src/adapters/mlx/mlx.dart';
import 'package:cow_brain/src/agent/agent_loop.dart';
import 'package:cow_brain/src/agent/agent_runner.dart';
import 'package:cow_brain/src/agent/agent_setup.dart';
import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/context/context_manager.dart';
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

  /// Interrupt handles for cancelling tool waits, keyed by sequence ID.
  final Map<int, Completer<void>> _toolWaitInterrupts = {};

  /// Pending tool result completers, keyed by tool call ID.
  final Map<String, Completer<ToolResult>> _pendingToolResults = {};

  BrainIsolateData get _data => _logic.get<BrainIsolateData>();
  BrainIsolateConfig get _config => _logic.get<BrainIsolateConfig>();

  void _setupBindings() {
    _binding
      ..onOutput<SendEventRequested>((output) => _sendEvent(output.event))
      ..onOutput<SendErrorRequested>((output) => _sendError(output.message))
      ..onOutput<StoreConfigRequested>((output) {
        _logic.blackboard.overwrite(output.config);
      })
      ..onOutput<StreamTurnRequested>(
        (output) => unawaited(_streamTurn(output.sequenceId)),
      )
      ..onOutput<CancelTurnRequested>(
        (output) => _cancelTurn(output.sequenceId),
      )
      ..onOutput<DisposeRuntimeRequested>((_) => _disposeRuntime())
      ..onOutput<ResetRuntimeRequested>((_) => _resetRuntime())
      ..onOutput<CompleteToolResultRequested>(
        (output) => _completeToolResult(output.result),
      )
      ..onOutput<CreateSequenceRequested>(
        (output) => _createSequence(output.request),
      )
      ..onOutput<DestroySequenceRequested>(
        (output) => _destroySequence(output.request),
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
        _logic.input(CancelInput(sequenceId: cancel.sequenceId));
      case BrainRequestType.reset:
        _logic.input(const ResetInput());
      case BrainRequestType.dispose:
        _logic.input(const DisposeInput());
      case BrainRequestType.createSequence:
        final createSeq = request.createSequence;
        if (createSeq == null) {
          _sendError('CreateSequence payload was missing.');
          return;
        }
        _logic.input(CreateSequenceInput(request: createSeq));
      case BrainRequestType.destroySequence:
        final destroySeq = request.destroySequence;
        if (destroySeq == null) {
          _sendError('DestroySequence payload was missing.');
          return;
        }
        _logic.input(DestroySequenceInput(request: destroySeq));
    }
  }

  bool _shouldCancel(int sequenceId) =>
      _data.cancelRequested[sequenceId] ?? false;

  Future<void> _streamTurn(int sequenceId) async {
    final agent = _config.agents[sequenceId];
    final conversation = _config.conversations[sequenceId];
    if (agent == null || conversation == null) {
      _logic.input(
        TurnFailed(
          error: 'Sequence $sequenceId does not exist.',
          sequenceId: sequenceId,
        ),
      );
      return;
    }

    try {
      await agent
          .runTurn(
            conversation,
            toolExecutor: (calls) => _executeToolCalls(sequenceId, calls),
            shouldCancel: () => _shouldCancel(sequenceId),
            maxSteps: _data.maxSteps[sequenceId] ?? 8,
            enableReasoning: _data.enableReasoning[sequenceId] ?? true,
          )
          .forEach(_sendEvent);
      _logic.input(TurnCompleted(sequenceId: sequenceId));
    } on Object catch (error) {
      _logic.input(
        TurnFailed(
          error: error.toString(),
          sequenceId: sequenceId,
        ),
      );
    }
  }

  Future<List<ToolResult>> _executeToolCalls(
    int sequenceId,
    List<ToolCall> calls,
  ) async {
    if (_shouldCancel(sequenceId)) throw const CancelledException();

    final interrupt = Completer<void>();
    _toolWaitInterrupts[sequenceId] = interrupt;

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
      _toolWaitInterrupts.remove(sequenceId);
      for (final call in calls) {
        _pendingToolResults.remove(call.id);
      }
    }
  }

  void _cancelTurn(int sequenceId) {
    _data.cancelRequested[sequenceId] = true;
    final interrupt = _toolWaitInterrupts[sequenceId];
    if (interrupt != null && !interrupt.isCompleted) {
      interrupt.complete();
    }
  }

  void _completeToolResult(ToolResult result) {
    final completer = _pendingToolResults.remove(result.toolCallId);
    if (completer == null || completer.isCompleted) return;
    completer.complete(result);
  }

  void _createSequence(CreateSequenceRequest request) {
    final seqId = request.sequenceId;
    final forkFrom = request.forkFrom;

    // Validate the sequence doesn't already exist.
    if (_config.conversations.containsKey(seqId)) {
      _sendError('Sequence $seqId already exists.');
      return;
    }

    // Get the runtime (implements InferenceRuntime).
    final raw = _config.runtime;
    if (raw is! InferenceRuntime) {
      _sendError('Runtime does not support multi-sequence.');
      return;
    }
    final runtime = raw as InferenceRuntime;

    try {
      if (forkFrom != null) {
        // Fork: copy KV cache + create new conversation from source.
        if (!_config.conversations.containsKey(forkFrom)) {
          _sendError('Source sequence $forkFrom does not exist.');
          return;
        }
        runtime.forkSequence(source: forkFrom, target: seqId);
        // Copy the conversation state.
        _config.conversations[seqId] = _config.conversations[forkFrom]!.copy();
      } else {
        // Create fresh sequence.
        runtime.createSequence(seqId);
        _config.conversations[seqId] = Conversation.initial();
      }

      // Create a new AgentLoop for this sequence.
      // We need the LlmAdapter and ToolRegistry from the existing agent.
      final existingAgent = _config.agents[0];
      if (existingAgent is AgentLoop) {
        final adapter = existingAgent.llm as InferenceAdapter;
        final newContextManager = SlidingWindowContextManager(
          counter: adapter.tokenCounter,
          safetyMarginTokens: _config.defaultSettings.safetyMarginTokens,
        );
        _config.agents[seqId] = AgentLoop(
          llm: existingAgent.llm,
          tools: existingAgent.tools,
          context: newContextManager,
          contextSize: existingAgent.contextSize,
          maxOutputTokens: existingAgent.maxOutputTokens,
          temperature: existingAgent.temperature,
          sequenceId: seqId,
        );
      } else {
        _sendError('Cannot create agent loop for sequence $seqId.');
        return;
      }

      // Initialize per-sequence data.
      _data
        ..cancelRequested[seqId] = false
        ..maxSteps[seqId] = _config.defaultSettings.maxSteps
        ..enableReasoning[seqId] = _config.enableReasoningDefault;
    } on Object catch (e) {
      _sendError('Failed to create sequence $seqId: $e');
    }
  }

  void _destroySequence(DestroySequenceRequest request) {
    final seqId = request.sequenceId;

    if (seqId == 0) {
      _sendError('Cannot destroy sequence 0.');
      return;
    }

    if (!_config.conversations.containsKey(seqId)) {
      _sendError('Sequence $seqId does not exist.');
      return;
    }

    try {
      final raw = _config.runtime;
      if (raw is InferenceRuntime) {
        (raw as InferenceRuntime).destroySequence(seqId);
      }

      _config.conversations.remove(seqId);
      _config.agents.remove(seqId);
      _data
        ..cancelRequested.remove(seqId)
        ..maxSteps.remove(seqId)
        ..enableReasoning.remove(seqId);
    } on Object catch (e) {
      _sendError('Failed to destroy sequence $seqId: $e');
    }
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
