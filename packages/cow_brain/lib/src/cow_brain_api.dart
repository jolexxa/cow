// Public API entrypoint for the isolate-backed brain harness.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/llama/llama_backend.dart';
import 'package:cow_brain/src/isolate/brain_harness.dart';
import 'package:cow_brain/src/isolate/models.dart';

class CowBrain {
  CowBrain({BrainHarness? harness})
    : _harness = harness ?? BrainHarness(),
      _backend = LlamaBackend(),
      _disposeBackend = true;

  CowBrain._withBackend({
    required BrainHarness? harness,
    required LlamaBackend backend,
    required bool disposeBackend,
  }) : _harness = harness ?? BrainHarness(),
       _backend = backend,
       _disposeBackend = disposeBackend;

  final BrainHarness _harness;
  final LlamaBackend _backend;
  final bool _disposeBackend;

  Future<void> init({
    required LlamaRuntimeOptions runtimeOptions,
    required LlamaProfileId profile,
    required List<ToolDefinition> tools,
    required AgentSettings settings,
    required bool enableReasoning,
  }) {
    _backend.ensureInitialized(
      libraryPath: runtimeOptions.libraryPath,
    );
    return _harness.init(
      runtimeOptions: runtimeOptions,
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
      if (_disposeBackend) {
        _backend.release();
      }
    });
  }
}

final class CowBrains<TKey> {
  CowBrains({String? libraryPath})
    : _backend = LlamaBackend(
        libraryPath: libraryPath,
      );

  final LlamaBackend _backend;
  final Map<TKey, CowBrain> _brains = <TKey, CowBrain>{};

  Iterable<TKey> get keys => _brains.keys;
  Iterable<CowBrain> get values => _brains.values;

  CowBrain create(TKey key, {BrainHarness? harness}) {
    final existing = _brains[key];
    if (existing != null) {
      return existing;
    }
    final brain = CowBrain._withBackend(
      harness: harness,
      backend: _backend,
      disposeBackend: false,
    );
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
    _backend.release();
  }
}
