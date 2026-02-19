// MLX runtime — implements InferenceRuntime for the MLX inference backend.
// Uses Apple's TokenIterator (via cow_mlx_generate_begin/next) for
// prefill, sampling, and streaming detokenization. The Dart side only
// handles stop-sequence detection and stream chunking.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/inference_adapter.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_bindings.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_client.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_handles.dart';
import 'package:cow_brain/src/adapters/stream_assembler.dart';
import 'package:cow_brain/src/adapters/stream_chunk.dart';
import 'package:cow_brain/src/isolate/brain_isolate.dart';
import 'package:cow_brain/src/isolate/models.dart';

/// MLX inference runtime.
///
/// Plugs into [InferenceAdapter] via the [InferenceRuntime] interface. The
/// prompt formatting and stream parsing layers are backend-agnostic, so they
/// work identically for both llama.cpp and MLX.
final class MlxRuntime implements InferenceRuntime, BrainRuntime {
  MlxRuntime({
    required int modelId,
    required MlxRuntimeOptions options,
    required MlxClientApi client,
    required MlxBindings bindings,
  }) : _options = options,
       _client = client {
    _handles = MlxHandles.fromModelId(
      modelId: modelId,
      bindings: bindings,
    );
    _handles.contextHandle = _client.createContext(
      _handles,
      options.contextSize,
    );
  }

  final MlxRuntimeOptions _options;
  final MlxClientApi _client;
  late final MlxHandles _handles;

  bool _disposed = false;
  bool _bosApplied = false;

  @override
  int countTokens(String prompt, {required bool addBos}) {
    _ensureNotDisposed();
    final tokens = _client.tokenize(
      _handles,
      prompt,
      addSpecial: addBos && !_bosApplied,
    );
    return tokens.length;
  }

  @override
  Stream<StreamChunk> generate({
    required String prompt,
    required List<String> stopSequences,
    required bool addBos,
    required bool requiresReset,
    required int reusePrefixMessageCount,
  }) async* {
    _ensureNotDisposed();

    if (requiresReset) {
      _client.resetContext(_handles, _options.contextSize);
      _bosApplied = false;
    }

    final promptTokens = _client.tokenize(
      _handles,
      prompt,
      addSpecial: addBos && !_bosApplied,
    );
    if (addBos) {
      _bosApplied = true;
    }

    // Begin generation — prefills prompt and creates TokenIterator.
    _client.generateBegin(_handles, promptTokens, _options.samplingOptions);

    final maxOutputTokens = _options.maxOutputTokensDefault;
    final assembler = StreamAssembler(stopSequences: stopSequences);

    for (var i = 0; i < maxOutputTokens; i += 1) {
      final piece = _client.generateNext(_handles);

      // null means generation is done (EOG or max tokens).
      if (piece == null) break;

      final chunk = assembler.addText(piece);
      if (chunk != null) {
        yield chunk;
        await _asyncBoundary();
      }
      if (assembler.stopped) break;
    }

    for (final chunk in assembler.flush()) {
      yield chunk;
      await _asyncBoundary();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    if (_handles.contextHandle >= 0) {
      _handles.bindings.freeContext(_handles.contextHandle);
      _handles.contextHandle = -1;
    }
    _disposed = true;
  }

  @override
  void reset() {
    _ensureNotDisposed();
    _client.resetContext(_handles, _options.contextSize);
    _bosApplied = false;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('MlxRuntime is already disposed');
    }
  }

  Future<void> _asyncBoundary() => Future<void>.delayed(Duration.zero);
}
