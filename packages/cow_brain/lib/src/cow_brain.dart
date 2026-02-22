// Public API entrypoint for the isolate-backed brain harness.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/llama/llama_bindings.dart';
import 'package:cow_brain/src/adapters/llama/llama_client.dart';
import 'package:cow_brain/src/isolate/brain_harness.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/model_server/model_server.dart';

class CowBrain {
  CowBrain({BrainHarness? harness})
    : _harness = harness ?? BrainHarness(),
      _ownsBackend = true;

  CowBrain._shared({
    required BrainHarness? harness,
  }) : _harness = harness ?? BrainHarness(),
       _ownsBackend = false;

  static LlamaBindings? _bindings;
  static int _backendRefCount = 0;

  final BrainHarness _harness;
  final bool _ownsBackend;
  bool _acquired = false;

  void _ensureBackendInitialized(String libraryPath) {
    if (_acquired) return;
    _acquired = true;
    if (_backendRefCount == 0) {
      _bindings = LlamaClient.openBindings(libraryPath: libraryPath);
      _bindings!.llama_backend_init();
    }
    _backendRefCount += 1;
  }

  void _releaseBackend() {
    if (!_acquired) return;
    _acquired = false;
    _backendRefCount -= 1;
    if (_backendRefCount == 0) {
      _bindings?.llama_backend_free();
      _bindings = null;
    }
  }

  Future<void> init({
    required int modelHandle,
    required BackendRuntimeOptions options,
    required ModelProfileId profile,
    required List<ToolDefinition> tools,
    required AgentSettings settings,
    required bool enableReasoning,
  }) {
    if (options is LlamaCppRuntimeOptions) {
      _ensureBackendInitialized(options.libraryPath);
    }
    return _harness.init(
      modelHandle: modelHandle,
      options: options,
      profile: profile,
      tools: tools,
      settings: settings,
      enableReasoning: enableReasoning,
    );
  }

  Stream<AgentEvent> runTurn({
    required Message userMessage,
    required AgentSettings settings,
    required bool enableReasoning,
  }) {
    return _harness.runTurn(
      userMessage: userMessage,
      settings: settings,
      enableReasoning: enableReasoning,
    );
  }

  void sendToolResult({
    required String turnId,
    required ToolResult toolResult,
  }) {
    _harness.sendToolResult(turnId: turnId, toolResult: toolResult);
  }

  void cancel(String turnId) {
    _harness.cancel(turnId);
  }

  void reset() {
    _harness.reset();
  }

  Future<void> dispose() {
    return _harness.dispose().whenComplete(() {
      if (_ownsBackend) {
        _releaseBackend();
      }
    });
  }
}

final class CowBrains<TKey> {
  CowBrains({required String libraryPath, required ModelServer modelServer})
    : _libraryPath = libraryPath,
      _modelServer = modelServer;

  final String _libraryPath;
  final ModelServer _modelServer;
  final Map<TKey, CowBrain> _brains = <TKey, CowBrain>{};

  final Map<String, LoadedModel> _models = {};

  Iterable<TKey> get keys => _brains.keys;
  Iterable<CowBrain> get values => _brains.values;

  /// Returns the model pointer for the given path.
  /// Throws if the model hasn't been loaded.
  int modelPointer(String modelPath) {
    final model = _models[modelPath];
    if (model == null) {
      throw StateError('Model not loaded: $modelPath');
    }
    return model.modelPointer;
  }

  /// Loads a model via the ModelServer. Can be called multiple times for
  /// different models. Returns the loaded model.
  ///
  /// Progress is reported via [onProgress] as a value from 0.0 to 1.0.
  /// If the model is already loaded, returns the existing model immediately.
  Future<LoadedModel> loadModel({
    required String modelPath,
    LlamaModelOptions modelOptions = const LlamaModelOptions(),
    InferenceBackend backend = InferenceBackend.llamaCpp,
    String? libraryPathOverride,
    ModelLoadProgressCallback? onProgress,
  }) async {
    // Return existing if already loaded.
    final existing = _models[modelPath];
    if (existing != null) return existing;

    final model = await _modelServer.loadModel(
      modelPath: modelPath,
      libraryPath: libraryPathOverride ?? _libraryPath,
      modelOptions: modelOptions,
      backend: backend,
      onProgress: onProgress,
    );
    _models[modelPath] = model;
    return model;
  }

  /// Creates a new brain with the given key.
  ///
  /// The brain can be created before [loadModel], but [loadModel] must be
  /// called before initializing the brain (since init requires modelPointer).
  /// If a brain with the key already exists, returns the existing brain.
  CowBrain create(TKey key, {BrainHarness? harness}) {
    final existing = _brains[key];
    if (existing != null) {
      return existing;
    }
    final brain = CowBrain._shared(harness: harness);
    _brains[key] = brain;
    return brain;
  }

  CowBrain? operator [](TKey key) => _brains[key];

  Future<void> remove(TKey key) async {
    final brain = _brains.remove(key);
    if (brain != null) {
      await brain.dispose();
    }
  }

  Future<void> dispose() async {
    final brains = _brains.values.toList(growable: false);
    _brains.clear();
    for (final brain in brains) {
      await brain.dispose();
    }
    for (final model in _models.values) {
      model.dispose();
    }
    _models.clear();
    await _modelServer.dispose();
  }
}
