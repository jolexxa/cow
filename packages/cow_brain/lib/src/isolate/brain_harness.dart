// Harness for spawning the brain isolate and proxying requests/events.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:isolate';

import 'package:cow_brain/src/isolate/brain_isolate.dart';
import 'package:cow_brain/src/isolate/models.dart';

final class BrainHarness {
  BrainHarness({BrainIsolateEntry? entrypoint})
    : _entrypoint = entrypoint ?? brainIsolateEntry;

  final BrainIsolateEntry _entrypoint;
  final ReceivePort _receivePort = ReceivePort();
  final ReceivePort _exitPort = ReceivePort();
  final ReceivePort _errorPort = ReceivePort();
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();
  final Completer<SendPort> _sendPortCompleter = Completer<SendPort>();
  late Isolate _isolate;
  late SendPort _sendPort;
  bool _disposed = false;
  bool _turnActive = false;
  bool _started = false;
  bool _initialized = false;

  Stream<AgentEvent> get events => _events.stream;

  Future<void> init({
    required int modelHandle,
    required BackendRuntimeOptions options,
    required ModelProfileId profile,
    required List<ToolDefinition> tools,
    required AgentSettings settings,
    required bool enableReasoning,
  }) async {
    _ensureNotDisposed();
    await _ensureStarted();

    final ready = Completer<void>();
    final sub = _events.stream.listen((event) {
      if (event.type == AgentEventType.ready) {
        ready.complete();
      }
    });

    _send(
      BrainRequest(
        type: BrainRequestType.init,
        init: InitRequest(
          modelHandle: modelHandle,
          options: options,
          profile: profile,
          tools: tools,
          settings: settings,
          enableReasoning: enableReasoning,
        ),
      ),
    );

    await ready.future;
    await sub.cancel();
    _initialized = true;
  }

  Stream<AgentEvent> runTurn({
    required Message userMessage,
    required AgentSettings settings,
    required bool enableReasoning,
  }) {
    _ensureNotDisposed();
    _ensureReady();
    if (_turnActive) {
      throw StateError('Turn already running.');
    }
    _turnActive = true;

    _send(
      BrainRequest(
        type: BrainRequestType.runTurn,
        runTurn: RunTurnRequest(
          userMessage: userMessage,
          settings: settings,
          enableReasoning: enableReasoning,
        ),
      ),
    );

    final controller = StreamController<AgentEvent>();
    String? turnId;
    late final StreamSubscription<AgentEvent> sub;
    sub = _events.stream.listen(
      (event) {
        turnId ??= event.turnId;
        if (turnId != null && event.turnId == turnId) {
          controller.add(event);
          if (event.type == AgentEventType.turnFinished) {
            _turnActive = false;
            unawaited(controller.close());
            unawaited(sub.cancel());
          }
        } else if (event.type == AgentEventType.error && turnId == null) {
          controller.add(event);
          _turnActive = false;
          unawaited(controller.close());
          unawaited(sub.cancel());
        }
      },
      onError: controller.addError,
    );

    return controller.stream;
  }

  void sendToolResult({
    required String turnId,
    required ToolResult toolResult,
  }) {
    _ensureNotDisposed();
    _ensureReady();
    _send(
      BrainRequest(
        type: BrainRequestType.toolResult,
        toolResult: ToolResultRequest(
          turnId: turnId,
          toolResult: toolResult,
        ),
      ),
    );
  }

  void cancel(String turnId) {
    _ensureNotDisposed();
    _ensureReady();
    _send(
      BrainRequest(
        type: BrainRequestType.cancel,
        cancel: CancelRequest(turnId: turnId),
      ),
    );
  }

  void reset() {
    _ensureNotDisposed();
    _ensureReady();
    _send(const BrainRequest(type: BrainRequestType.reset));
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (_started) {
      _send(const BrainRequest(type: BrainRequestType.dispose));
    }
    await _events.close();
    _receivePort.close();
    _exitPort.close();
    _errorPort.close();
    if (_started) {
      _isolate.kill(priority: Isolate.immediate);
    }
  }

  Future<void> _ensureStarted() async {
    if (_started) {
      return;
    }
    _receivePort.listen(_handleMessage);

    _exitPort.listen((_) {
      if (!_disposed) {
        _handleIsolateDeath('Isolate exited unexpectedly (native crash?)');
      }
    });

    _errorPort.listen((message) {
      final details = message is List ? message.join(': ') : '$message';
      if (!_disposed) {
        _handleIsolateDeath('Isolate error: $details');
      }
    });

    _isolate = await Isolate.spawn(
      _entrypoint,
      _receivePort.sendPort,
      onExit: _exitPort.sendPort,
      onError: _errorPort.sendPort,
    );
    _sendPort = await _sendPortCompleter.future;
    _started = true;
  }

  void _handleIsolateDeath(String details) {
    _turnActive = false;
    if (!_events.isClosed) {
      _events.addError(StateError(details));
    }
  }

  void _handleMessage(dynamic message) {
    if (message is SendPort) {
      if (!_sendPortCompleter.isCompleted) {
        _sendPortCompleter.complete(message);
      }
      return;
    }
    if (message is Map) {
      final payload = Map<String, Object?>.from(message);
      _events.add(AgentEvent.fromJson(payload));
    }
  }

  void _send(BrainRequest request) {
    _sendPort.send(request.toJson());
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('BrainHarness is disposed.');
    }
  }

  void _ensureReady() {
    if (!_initialized) {
      throw StateError('BrainHarness is not initialized. Call init first.');
    }
  }
}
