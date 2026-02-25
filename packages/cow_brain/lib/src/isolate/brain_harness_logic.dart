// Brain harness state machine — manages isolate lifecycle phases.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:isolate';

import 'package:cow_brain/src/isolate/brain_isolate.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:logic_blocks/logic_blocks.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Shims (overridable for testing)
// ---------------------------------------------------------------------------

@visibleForTesting
Future<Isolate> Function(
  void Function(SendPort) entrypoint,
  SendPort message, {
  SendPort? onExit,
  SendPort? onError,
})
spawnIsolate = defaultSpawnIsolate;

@visibleForTesting
Future<Isolate> defaultSpawnIsolate(
  void Function(SendPort) entrypoint,
  SendPort message, {
  SendPort? onExit,
  SendPort? onError,
}) => Isolate.spawn(entrypoint, message, onExit: onExit, onError: onError);

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

/// Per-turn routing state for a single active sequence.
final class TurnRouting {
  TurnRouting(this.controller);
  final StreamController<AgentEvent> controller;
  String? turnId;
}

final class BrainHarnessData {
  BrainHarnessData({required this.entrypoint});

  final BrainIsolateEntry entrypoint;
  BrainRequest? pendingInit;

  // Per-turn routing — keyed by sequenceId.
  final Map<int, TurnRouting> activeTurns = {};

  // Isolate lifecycle.
  final ReceivePort receivePort = ReceivePort();
  final ReceivePort exitPort = ReceivePort();
  final ReceivePort errorPort = ReceivePort();
  final StreamController<AgentEvent> events =
      StreamController<AgentEvent>.broadcast();
  Isolate? isolate;
  SendPort? sendPort;
  Completer<void>? initCompleter;
}

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

sealed class HarnessInput {
  const HarnessInput();
}

/// Start initialization — spawn isolate if needed, send init request.
final class HarnessInit extends HarnessInput {
  const HarnessInit({required this.request});
  final BrainRequest request;
}

/// Isolate spawned — store reference.
final class HarnessIsolateSpawned extends HarnessInput {
  const HarnessIsolateSpawned({required this.isolate});
  final Isolate isolate;
}

/// Isolate sent its SendPort.
final class HarnessSendPortReceived extends HarnessInput {
  const HarnessSendPortReceived({required this.sendPort});
  final SendPort sendPort;
}

/// An event was received from the isolate.
final class HarnessEventReceived extends HarnessInput {
  const HarnessEventReceived({required this.event});
  final AgentEvent event;
}

/// Start a turn on a sequence.
final class HarnessRunTurn extends HarnessInput {
  const HarnessRunTurn({required this.request, required this.sequenceId});
  final BrainRequest request;
  final int sequenceId;
}

/// Fire-and-forget message to send (toolResult, cancel, createSeq, etc).
final class HarnessSend extends HarnessInput {
  const HarnessSend({required this.request});
  final BrainRequest request;
}

/// Reset — clear active sequences and send reset message.
final class HarnessReset extends HarnessInput {
  const HarnessReset();
}

/// Isolate exited or errored unexpectedly.
final class HarnessIsolateDied extends HarnessInput {
  const HarnessIsolateDied({required this.details});
  final String details;
}

/// Dispose the harness.
final class HarnessDispose extends HarnessInput {
  const HarnessDispose();
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

sealed class HarnessOutput {
  const HarnessOutput();
}

/// Host should send this request to the isolate via SendPort.
final class SendToIsolate extends HarnessOutput {
  SendToIsolate({required this.sendPort, required this.request});
  final SendPort sendPort;
  final BrainRequest request;
}

/// Host should close ports and kill isolate.
final class CleanupIsolate extends HarnessOutput {
  CleanupIsolate({
    required this.wasStarted,
    required this.events,
    required this.receivePort,
    required this.exitPort,
    required this.errorPort,
    this.isolate,
  });
  final bool wasStarted;
  final StreamController<AgentEvent> events;
  final ReceivePort receivePort;
  final ReceivePort exitPort;
  final ReceivePort errorPort;
  final Isolate? isolate;
}

/// Host should close this turn's stream controller.
final class CloseTurnStream extends HarnessOutput {
  const CloseTurnStream({required this.controller});
  final StreamController<AgentEvent> controller;
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

sealed class BrainHarnessState extends StateLogic<BrainHarnessState> {
  BrainHarnessData get data => get<BrainHarnessData>();

  /// Outputs close requests for all per-turn controllers and clears the map.
  void closeAllTurns() {
    for (final turn in data.activeTurns.values) {
      output(CloseTurnStream(controller: turn.controller));
    }
    data.activeTurns.clear();
  }

  /// Builds a [CleanupIsolate] output from the current data.
  CleanupIsolate _cleanup({required bool wasStarted}) => CleanupIsolate(
    wasStarted: wasStarted,
    events: data.events,
    receivePort: data.receivePort,
    exitPort: data.exitPort,
    errorPort: data.errorPort,
    isolate: data.isolate,
  );
}

final class NotStartedState extends BrainHarnessState {
  NotStartedState() {
    onAny((_) {
      throw StateError('BrainHarness is not initialized. Call init first.');
    });

    on<HarnessInit>((input) {
      data
        ..pendingInit = input.request
        ..initCompleter = Completer<void>();
      async<Isolate>(
            spawnIsolate(
              data.entrypoint,
              data.receivePort.sendPort,
              onExit: data.exitPort.sendPort,
              onError: data.errorPort.sendPort,
            ),
          )
          .input((isolate) => HarnessIsolateSpawned(isolate: isolate))
          .errorInput(
            (err) => HarnessIsolateDied(details: 'Spawn failed: $err'),
          );
      return to<StartingState>();
    });

    on<HarnessDispose>((_) {
      output(_cleanup(wasStarted: false));
      return to<DisposedState>();
    });
  }
}

final class StartingState extends BrainHarnessState {
  StartingState() {
    onAny((_) {
      throw StateError('BrainHarness is not initialized. Call init first.');
    });

    on<HarnessIsolateSpawned>((input) {
      data.isolate = input.isolate;
      return toSelf();
    });

    on<HarnessSendPortReceived>((input) {
      data.sendPort = input.sendPort;
      final request = data.pendingInit!;
      data.pendingInit = null;
      output(SendToIsolate(sendPort: input.sendPort, request: request));
      return toSelf();
    });

    on<HarnessEventReceived>((input) {
      final event = input.event;
      if (event.type == AgentEventType.ready) {
        final completer = data.initCompleter;
        data.initCompleter = null;
        completer?.complete();
        if (!data.events.isClosed) {
          data.events.add(event);
        }
        return to<ReadyState>();
      }
      if (event.type == AgentEventType.error) {
        final completer = data.initCompleter;
        data.initCompleter = null;
        completer?.completeError(
          StateError('Init failed: ${(event as AgentError).error}'),
        );
        // Don't emit init errors on the events stream.
        return toSelf();
      }
      if (!data.events.isClosed) {
        data.events.add(event);
      }
      return toSelf();
    });

    on<HarnessIsolateDied>((input) {
      final completer = data.initCompleter;
      data.initCompleter = null;
      completer?.completeError(StateError(input.details));
      return to<DisposedState>();
    });

    on<HarnessDispose>((_) {
      final completer = data.initCompleter;
      data.initCompleter = null;
      completer?.completeError(
        StateError('BrainHarness was disposed during init.'),
      );
      output(_cleanup(wasStarted: true));
      return to<DisposedState>();
    });
  }
}

final class ReadyState extends BrainHarnessState {
  ReadyState() {
    // The spawn future can complete after we've already transitioned here.
    on<HarnessIsolateSpawned>((input) {
      data.isolate = input.isolate;
      return toSelf();
    });

    on<HarnessInit>((input) {
      closeAllTurns();
      data
        ..pendingInit = input.request
        ..initCompleter = Completer<void>();
      output(
        SendToIsolate(sendPort: data.sendPort!, request: input.request),
      );
      return to<StartingState>();
    });

    on<HarnessRunTurn>((input) {
      if (data.activeTurns.containsKey(input.sequenceId)) {
        throw StateError(
          'Turn already running on sequence ${input.sequenceId}.',
        );
      }
      data.activeTurns[input.sequenceId] = TurnRouting(
        StreamController<AgentEvent>(),
      );
      output(
        SendToIsolate(sendPort: data.sendPort!, request: input.request),
      );
      return toSelf();
    });

    on<HarnessSend>((input) {
      output(
        SendToIsolate(sendPort: data.sendPort!, request: input.request),
      );
      return toSelf();
    });

    on<HarnessReset>((_) {
      closeAllTurns();
      output(
        SendToIsolate(
          sendPort: data.sendPort!,
          request: const BrainRequest(type: BrainRequestType.reset),
        ),
      );
      return toSelf();
    });

    on<HarnessEventReceived>((input) {
      final event = input.event;

      // Always emit on broadcast stream.
      if (!data.events.isClosed) {
        data.events.add(event);
      }

      // Route to per-turn controller if active.
      final turn = data.activeTurns[event.sequenceId];
      if (turn != null) {
        turn.turnId ??= event.turnId;

        if (turn.turnId != null && event.turnId == turn.turnId) {
          turn.controller.add(event);
          if (event.type == AgentEventType.turnFinished) {
            output(CloseTurnStream(controller: turn.controller));
            data.activeTurns.remove(event.sequenceId);
          }
        } else if (event.type == AgentEventType.error && turn.turnId == null) {
          turn.controller.add(event);
          output(CloseTurnStream(controller: turn.controller));
          data.activeTurns.remove(event.sequenceId);
        }
      }

      return toSelf();
    });

    on<HarnessIsolateDied>((input) {
      closeAllTurns();
      if (!data.events.isClosed) {
        data.events.addError(StateError(input.details));
      }
      output(_cleanup(wasStarted: true));
      return to<DisposedState>();
    });

    on<HarnessDispose>((_) {
      closeAllTurns();
      output(
        SendToIsolate(
          sendPort: data.sendPort!,
          request: const BrainRequest(type: BrainRequestType.dispose),
        ),
      );
      output(_cleanup(wasStarted: true));
      return to<DisposedState>();
    });
  }
}

final class DisposedState extends BrainHarnessState {
  DisposedState() {
    onAny((_) => throw StateError('BrainHarness is disposed.'));

    on<HarnessDispose>((_) => toSelf());
  }
}

// ---------------------------------------------------------------------------
// Logic block
// ---------------------------------------------------------------------------

final class BrainHarnessLogic extends LogicBlock<BrainHarnessState> {
  BrainHarnessLogic({required BrainIsolateEntry entrypoint}) {
    final data = BrainHarnessData(entrypoint: entrypoint);
    set(data);

    // Port listeners feed inputs back to the logic block.
    data.receivePort.listen((message) {
      if (isStopped) return;
      if (message is SendPort) {
        input(HarnessSendPortReceived(sendPort: message));
        return;
      }
      if (message is Map) {
        final payload = Map<String, Object?>.from(message);
        final event = AgentEvent.fromJson(payload);
        input(HarnessEventReceived(event: event));
      }
    });

    data.exitPort.listen((_) {
      if (isStopped) return;
      input(
        const HarnessIsolateDied(
          details: 'Isolate exited unexpectedly (native crash?)',
        ),
      );
    });

    data.errorPort.listen((message) {
      if (isStopped) return;
      final details = message is List ? message.join(': ') : '$message';
      input(HarnessIsolateDied(details: 'Isolate error: $details'));
    });

    set(NotStartedState());
    set(StartingState());
    set(ReadyState());
    set(DisposedState());
  }

  @override
  Transition getInitialState() => to<NotStartedState>();

  // Public getters for the host

  BrainHarnessData get _data => get<BrainHarnessData>();

  Stream<AgentEvent> get events => _data.events.stream;

  Future<void> get initFuture => _data.initCompleter!.future;

  Stream<AgentEvent> turnStream(int sequenceId) =>
      _data.activeTurns[sequenceId]!.controller.stream;
}
