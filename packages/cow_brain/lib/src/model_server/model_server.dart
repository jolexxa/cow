// Public API for the model server.

import 'dart:async';
import 'dart:isolate';

import 'package:cow_brain/src/adapters/llama/llama_client.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/model_server/model_server_isolate.dart';
import 'package:cow_brain/src/model_server/model_server_messages.dart';

export 'model_server.dart';
export 'model_server_isolate.dart'
    show
        LlamaClientFactory,
        ModelServerIsolateTestHarness,
        modelServerClientFactoryOverride,
        modelServerIsolateEntry;
export 'model_server_messages.dart';

/// Test hook to override the isolate entry point.
void Function(SendPort)? modelServerIsolateEntryOverride;

/// A server that manages shared model loading across isolates.
///
/// Models are loaded once and can be shared across multiple inference
/// isolates. The server runs in its own isolate to keep the main isolate
/// responsive during model loading.
class ModelServer {
  ModelServer._({
    required Isolate isolate,
    required ReceivePort receivePort,
  }) : _isolate = isolate,
       _receivePort = receivePort;

  final Isolate _isolate;
  final ReceivePort _receivePort;
  late final SendPort _sendPort;
  bool _disposed = false;

  final Map<String, LoadedModel> _models = {};
  final Map<String, List<Completer<LoadedModel>>> _pendingLoads = {};
  final Map<String, ModelLoadProgressCallback?> _progressCallbacks = {};

  StreamSubscription<Object?>? _subscription;

  /// Spawns a new model server isolate.
  static Future<ModelServer> spawn() async {
    final receivePort = ReceivePort();
    final entryPoint =
        modelServerIsolateEntryOverride ?? modelServerIsolateEntry;
    final isolate = await Isolate.spawn(
      entryPoint,
      receivePort.sendPort,
    );

    final server = ModelServer._(
      isolate: isolate,
      receivePort: receivePort,
    );

    // Get the send port from the isolate. Use a completer so we can
    // continue listening to the stream after getting the first message.
    final sendPortCompleter = Completer<SendPort>();

    server._subscription = receivePort.listen((message) {
      if (!sendPortCompleter.isCompleted && message is SendPort) {
        sendPortCompleter.complete(message);
        return;
      }
      server._handleResponse(message);
    });

    // Can't cascade - await separates the two statements.
    // ignore: cascade_invocations
    server._sendPort = await sendPortCompleter.future;

    return server;
  }

  void _handleResponse(Object? message) {
    if (message is! Map) return;
    final response = ModelServerResponse.fromJson(
      Map<String, Object?>.from(message),
    );

    switch (response) {
      case ModelLoadedResponse():
        _handleModelLoaded(response);
      case ModelUnloadedResponse():
        _handleModelUnloaded(response);
      case LoadProgressResponse():
        _handleLoadProgress(response);
      case ModelServerError():
        _handleError(response.error);
    }
  }

  void _handleModelLoaded(ModelLoadedResponse response) {
    final model = LoadedModel._(
      modelPath: response.modelPath,
      modelPointer: response.modelPointer,
      server: this,
    );
    _models[response.modelPath] = model;

    // Guarantee 100% callback at end.
    final callback = _progressCallbacks.remove(response.modelPath);
    callback?.call(1);

    final completers = _pendingLoads.remove(response.modelPath);
    if (completers != null) {
      for (final completer in completers) {
        completer.complete(model);
      }
    }
  }

  void _handleModelUnloaded(ModelUnloadedResponse response) {
    _models.remove(response.modelPath);
  }

  void _handleLoadProgress(LoadProgressResponse response) {
    final callback = _progressCallbacks[response.modelPath];
    callback?.call(response.progress);
  }

  void _handleError(String error) {
    // Complete all pending loads with error.
    for (final completers in _pendingLoads.values) {
      for (final completer in completers) {
        completer.completeError(StateError(error));
      }
    }
    _pendingLoads.clear();
    _progressCallbacks.clear();
  }

  /// Loads a model and returns a handle to it.
  ///
  /// If the model is already loaded, returns the existing handle with an
  /// incremented reference count. Progress is reported via [onProgress].
  Future<LoadedModel> loadModel({
    required String modelPath,
    required String libraryPath,
    LlamaModelOptions modelOptions = const LlamaModelOptions(),
    InferenceBackend backend = InferenceBackend.llamaCpp,
    ModelLoadProgressCallback? onProgress,
  }) {
    _ensureNotDisposed();

    // Check if already loaded.
    final existing = _models[modelPath];
    if (existing != null) {
      return Future.value(existing);
    }

    // Check if already loading.
    final pending = _pendingLoads[modelPath];
    if (pending != null) {
      final completer = Completer<LoadedModel>();
      pending.add(completer);
      return completer.future;
    }

    // Start loading.
    final completer = Completer<LoadedModel>();
    _pendingLoads[modelPath] = [completer];
    _progressCallbacks[modelPath] = onProgress;

    // Guarantee 0% callback at start.
    onProgress?.call(0);

    _sendPort.send(
      LoadModelRequest(
        modelPath: modelPath,
        libraryPath: libraryPath,
        modelOptions: modelOptions,
        backend: backend,
      ).toJson(),
    );

    return completer.future;
  }

  /// Unloads a model, decrementing its reference count.
  ///
  /// The model is only freed when the reference count reaches zero.
  void unloadModel(String modelPath) {
    _ensureNotDisposed();
    _sendPort.send(
      UnloadModelRequest(modelPath: modelPath).toJson(),
    );
  }

  /// Disposes the model server and all loaded models.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _sendPort.send(const DisposeModelServerRequest().toJson());

    await _subscription?.cancel();
    _receivePort.close();
    _isolate.kill();
    _models.clear();
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('ModelServer has been disposed');
    }
  }
}

/// A handle to a loaded model.
///
/// The model pointer can be passed to inference isolates. Call [dispose]
/// when done to decrement the reference count.
class LoadedModel {
  LoadedModel._({
    required this.modelPath,
    required this.modelPointer,
    required ModelServer server,
  }) : _server = server;

  /// The path to the model file.
  final String modelPath;

  /// The native pointer to the loaded model.
  ///
  /// This can be passed to inference isolates as an int.
  final int modelPointer;

  final ModelServer _server;

  /// Decrements the reference count for this model.
  ///
  /// The model is freed when the count reaches zero.
  void dispose() {
    _server.unloadModel(modelPath);
  }
}
