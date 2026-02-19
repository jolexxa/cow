// MLX handle wrapper for cross-isolate model sharing.
// ignore_for_file: public_member_api_docs

import 'package:cow_brain/src/adapters/mlx/mlx_bindings.dart';

/// Bundles MLX native handles for a model + context.
///
/// Unlike `LlamaHandles` which uses raw FFI pointers, MLX handles are
/// integer IDs managed by a global registry in the Swift shim. This makes
/// them inherently safe for cross-isolate sharing.
final class MlxHandles {
  MlxHandles({
    required this.bindings,
    required this.modelHandle,
    required this.contextHandle,
  });

  /// Reconstruct handles from a model ID received from another isolate.
  factory MlxHandles.fromModelId({
    required int modelId,
    required MlxBindings bindings,
  }) {
    final modelHandle = bindings.modelFromId(modelId);
    if (modelHandle < 0) {
      throw StateError('Invalid MLX model ID: $modelId');
    }
    return MlxHandles(
      bindings: bindings,
      modelHandle: modelHandle,
      contextHandle: -1,
    );
  }

  final MlxBindings bindings;
  final int modelHandle;
  int contextHandle;

  /// The shareable model ID for cross-isolate communication.
  int get modelId => bindings.modelGetId(modelHandle);
}
