// ModelServer isolate implementation.
// ignore_for_file: public_member_api_docs

import 'dart:isolate';

import 'package:cow_brain/src/adapters/llama/llama_bindings.dart';
import 'package:cow_brain/src/adapters/llama/llama_client.dart';
import 'package:cow_brain/src/adapters/llama/llama_handles.dart';
import 'package:cow_brain/src/model_server/model_server_messages.dart';

/// Factory for creating [LlamaClientApi] instances.
typedef LlamaClientFactory =
    LlamaClientApi Function({
      required String libraryPath,
    });

// Test hook for overriding client factory.
LlamaClientFactory? modelServerClientFactoryOverride;

// coverage:ignore-start
LlamaClientApi _defaultClientFactory({required String libraryPath}) =>
    LlamaClient(libraryPath: libraryPath);
// coverage:ignore-end

/// Entry point for the model server isolate.
void modelServerIsolateEntry(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);
  final state = _ModelServerState(sendPort);
  receivePort.listen(state.handleMessage);
}

/// Internal state for the model server isolate.
class _ModelServerState {
  _ModelServerState(
    this._sendPort, {
    LlamaClientFactory? clientFactory,
  }) : _clientFactory =
           clientFactory ??
           modelServerClientFactoryOverride ??
           _defaultClientFactory;

  final SendPort _sendPort;
  final LlamaClientFactory _clientFactory;
  final Map<String, _LoadedModel> _models = {};
  LlamaBindings? _bindings;
  bool _backendInitialized = false;

  void handleMessage(Object? message) {
    if (message is! Map) return;
    final json = Map<String, Object?>.from(message);
    try {
      final request = ModelServerRequest.fromJson(json);
      switch (request) {
        case LoadModelRequest():
          _handleLoadModel(request);
        case UnloadModelRequest():
          _handleUnloadModel(request);
        case DisposeModelServerRequest():
          _handleDispose();
      }
    } on Object catch (e) {
      _sendError(e.toString());
    }
  }

  void _handleLoadModel(LoadModelRequest request) {
    // Check if already loaded.
    final existing = _models[request.modelPath];
    if (existing != null) {
      existing.refCount += 1;
      _sendResponse(
        ModelLoadedResponse(
          modelPath: request.modelPath,
          modelPointer: existing.pointer,
        ),
      );
      return;
    }

    // Initialize backend if needed.
    if (!_backendInitialized) {
      _bindings = LlamaClient.openBindings(libraryPath: request.libraryPath);
      _bindings!.llama_backend_init();
      _backendInitialized = true;
    }

    // Create client and load model.
    final client = _clientFactory(libraryPath: request.libraryPath);
    final handles = client.loadModel(
      modelPath: request.modelPath,
      modelOptions: request.modelOptions,
      onProgress: (progress) {
        _sendResponse(
          LoadProgressResponse(
            modelPath: request.modelPath,
            progress: progress,
          ),
        );
        return true; // Continue loading.
      },
    );

    final pointer = handles.model.address;
    _models[request.modelPath] = _LoadedModel(
      pointer: pointer,
      handles: handles,
      client: client,
    );

    _sendResponse(
      ModelLoadedResponse(
        modelPath: request.modelPath,
        modelPointer: pointer,
      ),
    );
  }

  void _handleUnloadModel(UnloadModelRequest request) {
    final model = _models[request.modelPath];
    if (model == null) {
      _sendError('Model not loaded: ${request.modelPath}');
      return;
    }

    model.refCount -= 1;
    if (model.refCount <= 0) {
      model.client.dispose(model.handles);
      _models.remove(request.modelPath);
    }

    _sendResponse(ModelUnloadedResponse(modelPath: request.modelPath));
  }

  void _handleDispose() {
    for (final model in _models.values) {
      model.client.dispose(model.handles);
    }
    _models.clear();
    if (_backendInitialized) {
      _bindings?.llama_backend_free();
      _bindings = null;
      _backendInitialized = false;
    }
  }

  void _sendResponse(ModelServerResponse response) {
    _sendPort.send(response.toJson());
  }

  void _sendError(String error) {
    _sendResponse(ModelServerError(error: error));
  }
}

class _LoadedModel {
  _LoadedModel({
    required this.pointer,
    required this.handles,
    required this.client,
  });

  final int pointer;
  final LlamaHandles handles;
  final LlamaClientApi client;
  int refCount = 1;
}

/// Test-only harness for driving a model server state without spawning an
/// isolate.
final class ModelServerIsolateTestHarness {
  ModelServerIsolateTestHarness(
    SendPort sendPort, {
    LlamaClientFactory? clientFactory,
  }) : _state = _ModelServerState(
         sendPort,
         clientFactory: clientFactory,
       );

  final _ModelServerState _state;

  void handleMessage(Object? message) {
    _state.handleMessage(message);
  }
}
