// Harness for spawning the brain isolate and proxying requests/events.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:isolate';

import 'package:cow_brain/src/isolate/brain_harness_logic.dart';
import 'package:cow_brain/src/isolate/brain_isolate.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:logic_blocks/logic_blocks.dart';

final class BrainHarness {
  BrainHarness({
    BrainIsolateEntry? entrypoint,
    Duration initTimeout = const Duration(seconds: 30),
  }) : _initTimeout = initTimeout {
    _logic = BrainHarnessLogic(
      entrypoint: entrypoint ?? brainIsolateEntry,
    );
    _binding = _logic.bind();
    _setupBindings();
    _logic.start();
  }

  final Duration _initTimeout;

  late final BrainHarnessLogic _logic;
  late final LogicBlockBinding<BrainHarnessState> _binding;

  Stream<AgentEvent> get events => _logic.events;

  void _setupBindings() {
    _binding
      ..onOutput<CloseTurnStream>(
        (output) => unawaited(output.controller.close()),
      )
      ..onOutput<SendToIsolate>(
        (output) => output.sendPort.send(output.request.toJson()),
      )
      ..onOutput<CleanupIsolate>((output) {
        if (!output.events.isClosed) {
          unawaited(output.events.close());
        }
        output.receivePort.close();
        output.exitPort.close();
        output.errorPort.close();
        if (output.wasStarted) {
          output.isolate?.kill(priority: Isolate.immediate);
        }
      });
  }

  Future<void> init({
    required int modelHandle,
    required BackendRuntimeOptions options,
    required ModelProfileId profile,
    required List<ToolDefinition> tools,
    required AgentSettings settings,
    required bool enableReasoning,
    required String systemPrompt,
  }) async {
    _logic.input(
      HarnessInit(
        request: BrainRequest(
          type: BrainRequestType.init,
          init: InitRequest(
            modelHandle: modelHandle,
            options: options,
            profile: profile,
            tools: tools,
            settings: settings,
            enableReasoning: enableReasoning,
            systemPrompt: systemPrompt,
          ),
        ),
      ),
    );

    await _logic.initFuture.timeout(
      _initTimeout,
      onTimeout: () => throw TimeoutException(
        'BrainHarness.init() timed out after '
        '${_initTimeout.inSeconds} seconds',
      ),
    );
  }

  Stream<AgentEvent> runTurn({
    required Message userMessage,
    required AgentSettings settings,
    required bool enableReasoning,
    int sequenceId = 0,
  }) {
    _logic.input(
      HarnessRunTurn(
        sequenceId: sequenceId,
        request: BrainRequest(
          type: BrainRequestType.runTurn,
          runTurn: RunTurnRequest(
            sequenceId: sequenceId,
            userMessage: userMessage,
            settings: settings,
            enableReasoning: enableReasoning,
          ),
        ),
      ),
    );

    return _logic.turnStream(sequenceId);
  }

  void sendToolResult({
    required String turnId,
    required ToolResult toolResult,
  }) {
    _logic.input(
      HarnessSend(
        request: BrainRequest(
          type: BrainRequestType.toolResult,
          toolResult: ToolResultRequest(
            turnId: turnId,
            toolResult: toolResult,
          ),
        ),
      ),
    );
  }

  void cancel({required String turnId, int sequenceId = 0}) {
    _logic.input(
      HarnessSend(
        request: BrainRequest(
          type: BrainRequestType.cancel,
          cancel: CancelRequest(sequenceId: sequenceId, turnId: turnId),
        ),
      ),
    );
  }

  void createSequence({required int sequenceId, int? forkFrom}) {
    _logic.input(
      HarnessSend(
        request: BrainRequest(
          type: BrainRequestType.createSequence,
          createSequence: CreateSequenceRequest(
            sequenceId: sequenceId,
            forkFrom: forkFrom,
          ),
        ),
      ),
    );
  }

  void destroySequence(int sequenceId) {
    _logic.input(
      HarnessSend(
        request: BrainRequest(
          type: BrainRequestType.destroySequence,
          destroySequence: DestroySequenceRequest(sequenceId: sequenceId),
        ),
      ),
    );
  }

  void reset() {
    _logic.input(const HarnessReset());
  }

  Future<void> dispose() async {
    _logic.input(const HarnessDispose());
  }
}
