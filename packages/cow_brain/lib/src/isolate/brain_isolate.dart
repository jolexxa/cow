// Isolate entrypoint and session for running the brain runtime.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:isolate';

import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:cow_brain/src/agent/agent_runner.dart';
import 'package:cow_brain/src/agent/agent_setup.dart';
import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/core/conversation.dart';
import 'package:cow_brain/src/core/llm_adapter.dart';
import 'package:cow_brain/src/core/model_output.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/tools/tool_registry.dart';

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
      required LlamaRuntimeOptions runtimeOptions,
      required LlamaProfileId profile,
      required ToolRegistry tools,
      required Conversation conversation,
      required int contextSize,
      required int maxOutputTokens,
      required double temperature,
      required int safetyMarginTokens,
      required int maxSteps,
    });

// Test hook to override the runtime factory without loading native libraries.
LlamaClientApi? brainRuntimeClientOverride;
LlamaCppRuntime Function(LlamaRuntimeOptions options) brainRuntimeFactory =
    _createRuntime;

LlamaCppRuntime _createRuntime(LlamaRuntimeOptions options) =>
    LlamaCppRuntime(options: options, client: brainRuntimeClientOverride);

abstract interface class BrainRuntime {
  void reset();
  void dispose();
}

void brainIsolateEntry(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);
  final session = _BrainSession(sendPort);
  receivePort.listen(session.handleMessage);
}

AgentBundle _createDefaultBundle({
  required LlamaRuntimeOptions runtimeOptions,
  required LlamaProfileId profile,
  required ToolRegistry tools,
  required Conversation conversation,
  required int contextSize,
  required int maxOutputTokens,
  required double temperature,
  required int safetyMarginTokens,
  required int maxSteps,
}) {
  final bundle = createQwenAgent(
    runtimeOptions: runtimeOptions,
    profile: LlamaProfiles.profileFor(profile),
    tools: tools,
    conversation: conversation,
    contextSize: contextSize,
    maxOutputTokens: maxOutputTokens,
    temperature: temperature,
    safetyMarginTokens: safetyMarginTokens,
    maxSteps: maxSteps,
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

final class _BrainSession {
  _BrainSession(
    this._out, {
    AgentBundleFactory? bundleFactory,
  }) : _bundleFactory = bundleFactory ?? _createDefaultBundle;

  final SendPort _out;
  late BrainRuntime _runtime;
  late AgentRunner _agent;
  late Conversation _conversation;
  final AgentBundleFactory _bundleFactory;

  late AgentSettings _defaultSettings;
  late LlamaRuntimeOptions _runtimeOptions;
  late bool _enableReasoningDefault;
  bool _initialized = false;
  bool _turnActive = false;
  bool _cancelRequested = false;
  late Completer<void> _cancelCompleter;
  final Map<String, Completer<ToolResult>> _pendingToolResults =
      <String, Completer<ToolResult>>{};

  void handleMessage(Object? message) {
    if (message is! Map) return;
    final payload = Map<String, Object?>.from(message);
    final request = BrainRequest.fromJson(payload);
    switch (request.type) {
      case BrainRequestType.init:
        _handleInit(request.init);
      case BrainRequestType.runTurn:
        _handleRunTurn(request.runTurn);
      case BrainRequestType.toolResult:
        _handleToolResult(request.toolResult);
      case BrainRequestType.cancel:
        _handleCancel(request.cancel);
      case BrainRequestType.reset:
        _handleReset();
      case BrainRequestType.dispose:
        _handleDispose();
    }
  }

  void _handleInit(InitRequest? init) {
    if (init == null) {
      _sendError('Init payload was missing.');
      return;
    }
    _defaultSettings = init.settings;
    _runtimeOptions = init.runtimeOptions;
    final contextSize = _runtimeOptions.contextOptions.contextSize;
    final maxOutputTokensDefault = _runtimeOptions.maxOutputTokensDefault;
    final temperatureDefault =
        _runtimeOptions.samplingOptions.temperature ?? 0.7;
    _enableReasoningDefault = init.enableReasoning;
    if (_initialized) {
      _disposeRuntime();
    }
    final runtimeOptions = init.runtimeOptions;
    final tools = ToolRegistry();
    for (final tool in init.tools) {
      tools.register(
        tool,
        (_) => throw StateError('Tool execution is handled by the client.'),
      );
    }

    final bundle = _bundleFactory(
      runtimeOptions: runtimeOptions,
      profile: init.profile,
      tools: tools,
      conversation: Conversation.initial(),
      contextSize: contextSize,
      maxOutputTokens: maxOutputTokensDefault,
      temperature: temperatureDefault,
      safetyMarginTokens: init.settings.safetyMarginTokens,
      maxSteps: init.settings.maxSteps,
    );

    _runtime = bundle.runtime;
    _agent = bundle.agent;
    _agent.enableReasoning = _enableReasoningDefault;
    _conversation = bundle.conversation;
    _initialized = true;

    _sendEvent(const AgentReady());
  }

  void _handleRunTurn(RunTurnRequest? request) {
    if (request == null) {
      _sendError('RunTurn payload was missing.');
      return;
    }
    if (!_initialized) {
      _sendError('Brain is not initialized.');
      return;
    }
    if (_turnActive) {
      _sendError('Turn already running.');
      return;
    }

    _turnActive = true;
    _cancelRequested = false;
    _cancelCompleter = Completer<void>();

    final userMessage = request.userMessage;
    if (userMessage.role != Role.user) {
      _sendError('run_turn requires a user message.');
      _turnActive = false;
      return;
    }
    _conversation.addUser(userMessage.content, name: userMessage.name);

    _agent
      ..maxSteps = request.settings.maxSteps
      ..toolExecutor = _executeToolCalls
      ..shouldCancel = (() => _cancelRequested)
      ..enableReasoning = request.enableReasoning;

    unawaited(_streamTurn());
  }

  Future<void> _streamTurn() async {
    try {
      await _agent.runTurn(_conversation).forEach(_sendEvent);
    } on Object catch (error) {
      _sendError(error.toString());
    } finally {
      _turnActive = false;
      _cancelRequested = false;
    }
  }

  Future<List<ToolResult>> _executeToolCalls(
    List<ToolCall> calls,
  ) async {
    if (_cancelRequested) throw const CancelledException();
    final futures = <Future<ToolResult>>[];
    for (final call in calls) {
      final completer = Completer<ToolResult>();
      _pendingToolResults[call.id] = completer;
      futures.add(completer.future);
    }

    final cancelFuture = _cancelCompleter.future.then<List<ToolResult>>(
      (_) => throw const CancelledException(),
    );

    try {
      return await Future.any<List<ToolResult>>([
        Future.wait(futures),
        cancelFuture,
      ]);
    } finally {
      for (final call in calls) {
        _pendingToolResults.remove(call.id);
      }
    }
  }

  void _handleToolResult(ToolResultRequest? request) {
    if (request == null) {
      _sendError('ToolResult payload was missing.');
      return;
    }
    final result = request.toolResult;
    final completer = _pendingToolResults.remove(result.toolCallId);
    if (completer == null || completer.isCompleted) return;
    completer.complete(result);
  }

  void _handleCancel(CancelRequest? request) {
    if (request == null) {
      _sendError('Cancel payload was missing.');
      return;
    }
    _cancelRequested = true;
    if (_turnActive && !_cancelCompleter.isCompleted) {
      _cancelCompleter.complete();
    }
  }

  void _handleReset() {
    if (!_initialized) {
      _sendError('Brain is not initialized.');
      return;
    }
    _cancelRequested = true;
    if (_turnActive && !_cancelCompleter.isCompleted) {
      _cancelCompleter.complete();
    }
    _pendingToolResults.clear();

    _conversation = Conversation.initial();
    _agent
      ..maxSteps = _defaultSettings.maxSteps
      ..toolExecutor = _executeToolCalls
      ..shouldCancel = (() => _cancelRequested)
      ..enableReasoning = _enableReasoningDefault;
    _runtime.reset();
  }

  void _handleDispose() {
    _cancelRequested = true;
    if (_turnActive && !_cancelCompleter.isCompleted) {
      _cancelCompleter.complete();
    }
    _pendingToolResults.clear();
    if (_initialized) {
      _disposeRuntime();
      _initialized = false;
    }
  }

  void _disposeRuntime() {
    _runtime.dispose();
  }

  void _sendEvent(AgentEvent event) {
    _out.send(event.toJson());
  }

  void _sendError(String message) {
    _out.send(AgentError(error: message).toJson());
  }
}

/// Test-only harness for driving a brain session without spawning an isolate.
final class BrainSessionTestHarness {
  BrainSessionTestHarness(
    SendPort sendPort, {
    AgentBundleFactory? bundleFactory,
  }) : _session = _BrainSession(
         sendPort,
         bundleFactory: bundleFactory,
       );

  final _BrainSession _session;

  void handleMessage(Object? message) {
    _session.handleMessage(message);
  }
}
