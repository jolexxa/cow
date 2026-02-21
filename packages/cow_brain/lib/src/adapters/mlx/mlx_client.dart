// MLX client — high-level operations over the CowMLX native library.
// ignore_for_file: public_member_api_docs

import 'dart:ffi';

import 'package:cow_brain/src/adapters/mlx/mlx_bindings.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_handles.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:ffi/ffi.dart';
import 'package:mlx_dart/mlx_dart.dart';

/// Callback for model loading progress.
/// Returns true to continue loading, false to cancel.
typedef MlxModelLoadProgressCallback = bool Function(double progress);

abstract class MlxClientApi {
  MlxHandles loadModel({
    required String modelPath,
    MlxModelLoadProgressCallback? onProgress,
  });

  List<int> tokenize(
    MlxHandles handles,
    String text, {
    bool addSpecial,
  });

  int createContext(MlxHandles handles, int maxTokens);

  void resetContext(MlxHandles handles, int maxTokens);

  bool isEog(MlxHandles handles, int token);

  /// Begin a generation session — prefills the prompt and creates
  /// the TokenIterator on the native side.
  ///
  /// The native side compares incoming tokens against the cached
  /// sequence to find the common prefix, trims diverged cache entries,
  /// and only prefills new tokens.
  void generateBegin(
    MlxHandles handles,
    List<int> tokens,
    SamplingOptions options,
  );

  /// Advance generation by one token. Returns raw token bytes (not yet
  /// decoded as UTF-8), an empty list for control tokens, or null when done.
  /// The caller must feed these bytes through a chunked `Utf8Decoder`.
  List<int>? generateNext(MlxHandles handles, {int bufferSize});

  void dispose(MlxHandles handles);
}

final class MlxClient implements MlxClientApi {
  MlxClient({required this.libraryPath});

  final String libraryPath;

  MlxBindings? _bindings;
  bool _initialized = false;

  static MlxBindings Function({required String libraryPath}) openBindings =
      MlxBindingsLoader.open;

  MlxBindings _ensureBindings() {
    if (_bindings != null) return _bindings!;
    _bindings = openBindings(libraryPath: libraryPath);
    if (!_initialized) {
      _bindings!.init_();
      _initialized = true;
    }
    return _bindings!;
  }

  @override
  MlxHandles loadModel({
    required String modelPath,
    MlxModelLoadProgressCallback? onProgress,
  }) {
    final b = _ensureBindings();

    NativeCallable<cow_mlx_progress_fnFunction>? nativeCallback;
    if (onProgress != null) {
      nativeCallback = NativeCallable<cow_mlx_progress_fnFunction>.isolateLocal(
        // coverage:ignore-start
        (double progress, Pointer<Void> userData) => onProgress(progress),
        // coverage:ignore-end
        exceptionalReturn: false,
      );
    }

    final pathPtr = modelPath.toNativeUtf8();
    final handle = b.loadModel(
      pathPtr,
      nativeCallback?.nativeFunction ?? nullptr,
      nullptr,
    );
    calloc.free(pathPtr);
    nativeCallback?.close();

    if (handle < 0) {
      final error = b.getError() ?? 'Unknown error';
      throw StateError('Failed to load MLX model: $error');
    }

    return MlxHandles(
      bindings: b,
      modelHandle: handle,
      contextHandle: -1,
    );
  }

  @override
  List<int> tokenize(
    MlxHandles handles,
    String text, {
    bool addSpecial = true,
  }) {
    final b = handles.bindings;
    final textPtr = text.toNativeUtf8();
    final textLen = textPtr.length;

    // First call to get token count.
    var maxTokens = textLen + 16;
    var tokensPtr = calloc<Int32>(maxTokens);

    var n = b.tokenize(
      handles.modelHandle,
      textPtr,
      textLen,
      tokensPtr,
      maxTokens,
      addSpecial,
    );

    if (n < 0 && n != -1) {
      // Buffer too small — retry with correct size.
      calloc.free(tokensPtr);
      maxTokens = -n;
      tokensPtr = calloc<Int32>(maxTokens);
      n = b.tokenize(
        handles.modelHandle,
        textPtr,
        textLen,
        tokensPtr,
        maxTokens,
        addSpecial,
      );
    }
    calloc.free(textPtr);

    if (n < 0) {
      calloc.free(tokensPtr);
      throw StateError('MLX tokenization failed');
    }

    final result = tokensPtr.asTypedList(n).toList(growable: false);
    calloc.free(tokensPtr);
    return result;
  }

  @override
  int createContext(MlxHandles handles, int maxTokens) {
    final b = handles.bindings;
    final ctx = b.createContext(handles.modelHandle, maxTokens);
    if (ctx < 0) {
      throw StateError('Failed to create MLX context');
    }
    return ctx;
  }

  @override
  void resetContext(MlxHandles handles, int maxTokens) {
    final b = handles.bindings;
    if (handles.contextHandle >= 0) {
      b.freeContext(handles.contextHandle);
    }
    handles.contextHandle = createContext(handles, maxTokens);
  }

  @override
  bool isEog(MlxHandles handles, int token) {
    return handles.bindings.isEog(handles.modelHandle, token);
  }

  @override
  void generateBegin(
    MlxHandles handles,
    List<int> tokens,
    SamplingOptions options,
  ) {
    if (tokens.isEmpty) return;
    final b = handles.bindings;
    final tokensPtr = calloc<Int32>(tokens.length);
    for (var i = 0; i < tokens.length; i++) {
      tokensPtr[i] = tokens[i];
    }

    final ok = b.generateBegin(
      handles.contextHandle,
      tokensPtr,
      tokens.length,
      options.temperature ?? 0.7,
      options.topP ?? 0.95,
      options.topK ?? 40,
      options.minP ?? 0.05,
      options.penaltyRepeat ?? 1.1,
      options.penaltyLastN ?? 64,
      options.seed,
    );
    calloc.free(tokensPtr);

    if (!ok) {
      final error = b.getError() ?? 'Unknown error';
      throw StateError('MLX generate_begin failed: $error');
    }
  }

  @override
  List<int>? generateNext(MlxHandles handles, {int bufferSize = 256}) {
    final b = handles.bindings;
    var buf = calloc<Uint8>(bufferSize);
    var n = b.generateNext(handles.contextHandle, buf.cast(), bufferSize);

    // -1 means done (EOG or max tokens).
    if (n == -1) {
      calloc.free(buf);
      return null;
    }

    // Buffer too small — retry.
    if (n < -1) {
      calloc.free(buf);
      final needed = -n;
      buf = calloc<Uint8>(needed);
      n = b.generateNext(handles.contextHandle, buf.cast(), needed);
    }

    // 0 means control token (no bytes).
    if (n <= 0) {
      calloc.free(buf);
      return n == 0 ? const <int>[] : null;
    }

    // Return raw bytes — caller handles UTF-8 reassembly.
    final result = buf.asTypedList(n).toList(growable: false);
    calloc.free(buf);
    return result;
  }

  @override
  void dispose(MlxHandles handles) {
    final b = handles.bindings;
    if (handles.contextHandle >= 0) {
      b.freeContext(handles.contextHandle);
      handles.contextHandle = -1;
    }
    b.freeModel(handles.modelHandle);
  }
}
