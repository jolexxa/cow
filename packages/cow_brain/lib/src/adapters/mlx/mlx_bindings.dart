// MLX native bindings adapter.
// ignore_for_file: public_member_api_docs, avoid_positional_boolean_parameters

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:mlx_dart/mlx_dart.dart';

/// Abstract bindings for the CowMLX native library.
///
/// Mirrors the pattern of `LlamaBindings` — an abstract class that wraps
/// every native function the app needs, with a concrete adapter that
/// delegates to the raw FFI bindings.
abstract class MlxBindings {
  bool init_();
  void shutdown();

  String? getError();

  int loadModel(
    Pointer<Utf8> path,
    cow_mlx_progress_fn progressCb,
    Pointer<Void> userData,
  );
  void freeModel(int handle);
  int modelGetId(int handle);
  int modelFromId(int modelId);

  int createContext(int modelHandle, int maxTokens);
  void freeContext(int contextHandle);
  bool resetContext(int contextHandle);

  int tokenize(
    int modelHandle,
    Pointer<Utf8> text,
    int textLen,
    Pointer<Int32> outTokens,
    int maxTokens,
    bool addSpecial,
  );
  bool isEog(int modelHandle, int token);

  bool generateBegin(
    int contextHandle,
    Pointer<Int32> tokens,
    int tokenCount,
    double temperature,
    double topP,
    int topK,
    double minP,
    double repeatPenalty,
    int repeatWindow,
    int seed,
  );
  int generateNext(
    int contextHandle,
    Pointer<Utf8> buf,
    int bufLen,
  );
}

/// Concrete adapter delegating to [CowMlxBindings].
// coverage:ignore-start
final class MlxBindingsAdapter implements MlxBindings {
  MlxBindingsAdapter(this._ffi);

  final CowMlxBindings _ffi;

  @override
  bool init_() => _ffi.cow_mlx_init();

  @override
  void shutdown() => _ffi.cow_mlx_shutdown();

  @override
  String? getError() {
    final ptr = _ffi.cow_mlx_get_error();
    if (ptr == nullptr) return null;
    return ptr.cast<Utf8>().toDartString();
  }

  @override
  int loadModel(
    Pointer<Utf8> path,
    cow_mlx_progress_fn progressCb,
    Pointer<Void> userData,
  ) => _ffi.cow_mlx_load_model(path.cast(), progressCb, userData);

  @override
  void freeModel(int handle) => _ffi.cow_mlx_free_model(handle);

  @override
  int modelGetId(int handle) => _ffi.cow_mlx_model_get_id(handle);

  @override
  int modelFromId(int modelId) => _ffi.cow_mlx_model_from_id(modelId);

  @override
  int createContext(int modelHandle, int maxTokens) =>
      _ffi.cow_mlx_create_context(modelHandle, maxTokens);

  @override
  void freeContext(int contextHandle) =>
      _ffi.cow_mlx_free_context(contextHandle);

  @override
  bool resetContext(int contextHandle) =>
      _ffi.cow_mlx_reset_context(contextHandle);

  @override
  int tokenize(
    int modelHandle,
    Pointer<Utf8> text,
    int textLen,
    Pointer<Int32> outTokens,
    int maxTokens,
    bool addSpecial,
  ) => _ffi.cow_mlx_tokenize(
    modelHandle,
    text.cast(),
    textLen,
    outTokens,
    maxTokens,
    addSpecial,
  );

  @override
  bool isEog(int modelHandle, int token) =>
      _ffi.cow_mlx_is_eog(modelHandle, token);

  @override
  bool generateBegin(
    int contextHandle,
    Pointer<Int32> tokens,
    int tokenCount,
    double temperature,
    double topP,
    int topK,
    double minP,
    double repeatPenalty,
    int repeatWindow,
    int seed,
  ) => _ffi.cow_mlx_generate_begin(
    contextHandle,
    tokens,
    tokenCount,
    temperature,
    topP,
    topK,
    minP,
    repeatPenalty,
    repeatWindow,
    seed,
  );

  @override
  int generateNext(
    int contextHandle,
    Pointer<Utf8> buf,
    int bufLen,
  ) => _ffi.cow_mlx_generate_next(contextHandle, buf.cast(), bufLen);
}

// coverage:ignore-end

/// Factory for opening MLX bindings from a dynamic library path.
// coverage:ignore-start
final class MlxBindingsLoader {
  static MlxBindings open({required String libraryPath}) {
    final dylib = DynamicLibrary.open(libraryPath);
    return MlxBindingsAdapter(CowMlxBindings(dylib));
  }
}

// coverage:ignore-end
