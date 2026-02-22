// ModelServer isolate implementation.
// ignore_for_file: public_member_api_docs

import 'dart:isolate';

import 'package:cow_brain/src/adapters/llama/llama_bindings.dart';
import 'package:cow_brain/src/adapters/llama/llama_client.dart';
import 'package:cow_brain/src/adapters/llama/llama_handles.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_client.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_handles.dart';
import 'package:cow_brain/src/isolate/models.dart';
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

    switch (request.backend) {
      case InferenceBackend.llamaCpp:
        _handleLoadLlamaModel(request);
      case InferenceBackend.mlx:
        _handleLoadMlxModel(request);
    }
  }

  void _handleLoadLlamaModel(LoadModelRequest request) {
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
      backend: _LlamaState(handles: handles, client: client),
    );

    _sendResponse(
      ModelLoadedResponse(
        modelPath: request.modelPath,
        modelPointer: pointer,
      ),
    );
  }

  void _handleLoadMlxModel(LoadModelRequest request) {
    final mlxClient = MlxClient(libraryPath: request.libraryPath);
    final handles = mlxClient.loadModel(
      modelPath: request.modelPath,
      onProgress: (progress) {
        _sendResponse(
          LoadProgressResponse(
            modelPath: request.modelPath,
            progress: progress,
          ),
        );
        return true;
      },
    );

    final modelId = handles.modelId;
    _models[request.modelPath] = _LoadedModel(
      pointer: modelId,
      backend: _MlxState(handles: handles, client: mlxClient),
    );

    _sendResponse(
      ModelLoadedResponse(
        modelPath: request.modelPath,
        modelPointer: modelId,
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
      model.dispose();
      _models.remove(request.modelPath);
    }

    _sendResponse(ModelUnloadedResponse(modelPath: request.modelPath));
  }

  void _handleDispose() {
    for (final model in _models.values) {
      model.dispose();
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

sealed class _BackendState {
  void dispose();
}

final class _LlamaState extends _BackendState {
  _LlamaState({required this.handles, required this.client});
  final LlamaHandles handles;
  final LlamaClientApi client;

  @override
  void dispose() => client.dispose(handles);
}

final class _MlxState extends _BackendState {
  _MlxState({required this.handles, required this.client});
  final MlxHandles handles;
  final MlxClientApi client;

  @override
  void dispose() => client.dispose(handles);
}

class _LoadedModel {
  _LoadedModel({required this.pointer, required this.backend});

  final int pointer;
  final _BackendState backend;
  int refCount = 1;

  void dispose() => backend.dispose();
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
