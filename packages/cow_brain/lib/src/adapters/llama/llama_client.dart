// This is a direct llama.cpp bridge; we keep docs light for now.
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:cow_brain/src/adapters/llama/llama_bindings.dart';
import 'package:cow_brain/src/adapters/llama/llama_handles.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:ffi/ffi.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path/path.dart' as p;

/// Callback for model loading progress.
/// Returns true to continue loading, false to cancel.
typedef ModelLoadProgressCallback = bool Function(double progress);

abstract class LlamaClientApi {
  LlamaHandles loadModel({
    required String modelPath,
    required LlamaModelOptions modelOptions,
    ModelLoadProgressCallback? onProgress,
  });

  List<int> tokenize(
    LlamaHandles handles,
    String text, {
    bool addSpecial,
    bool parseSpecial,
  });

  void resetContext(
    LlamaHandles handles,
    LlamaContextOptions options,
  );

  Pointer<llama_context> createContext(
    LlamaHandles handles,
    LlamaContextOptions options,
  );

  void decode(
    LlamaHandles handles,
    Pointer<llama_context> context,
    List<int> tokens,
  );

  int sampleNext(
    LlamaHandles handles,
    LlamaSamplerChain sampler,
  );

  Uint8List tokenToBytes(
    LlamaHandles handles,
    int token, {
    int bufferSize,
  });

  void dispose(LlamaHandles handles);
}

final class LlamaClient implements LlamaClientApi {
  LlamaClient({required this.libraryPath});

  final String libraryPath;

  LlamaBindings? _bindings;

  static LlamaBindings Function({required String libraryPath}) openBindings =
      LlamaBindingsLoader.open;

  LlamaBindings _ensureBindings() {
    if (_bindings != null) return _bindings!;
    _bindings = openBindings(libraryPath: libraryPath);
    final dirPath = p.dirname(libraryPath).toNativeUtf8().cast<Char>();
    _bindings!.ggml_backend_load_all_from_path(dirPath);
    calloc.free(dirPath);
    return _bindings!;
  }

  @override
  LlamaHandles loadModel({
    required String modelPath,
    required LlamaModelOptions modelOptions,
    ModelLoadProgressCallback? onProgress,
  }) {
    final b = _ensureBindings();
    if (modelOptions.numa != null) {
      b.llama_numa_init(ggml_numa_strategy.fromValue(modelOptions.numa!));
    }

    final modelParams = b.llama_model_default_params();
    if (modelOptions.nGpuLayers != null) {
      modelParams.n_gpu_layers = modelOptions.nGpuLayers!;
    }
    if (modelOptions.mainGpu != null) {
      modelParams.main_gpu = modelOptions.mainGpu!;
    }
    if (modelOptions.useMmap != null) {
      modelParams.use_mmap = modelOptions.useMmap!;
    }
    if (modelOptions.useMlock != null) {
      modelParams.use_mlock = modelOptions.useMlock!;
    }
    if (modelOptions.checkTensors != null) {
      modelParams.check_tensors = modelOptions.checkTensors!;
    }

    // Set up progress callback if provided
    NativeCallable<llama_progress_callbackFunction>? nativeCallback;
    if (onProgress != null) {
      nativeCallback =
          NativeCallable<llama_progress_callbackFunction>.isolateLocal(
            // coverage:ignore-start
            (double progress, Pointer<Void> userData) => onProgress(progress),
            // coverage:ignore-end
            exceptionalReturn: false,
          );
      modelParams.progress_callback = nativeCallback.nativeFunction;
    }

    final modelPathPtr = modelPath.toNativeUtf8().cast<Char>();
    final model = b.llama_load_model_from_file(modelPathPtr, modelParams);
    calloc.free(modelPathPtr);

    // Clean up native callback
    nativeCallback?.close();

    if (model == nullptr) {
      throw StateError('Failed to load model: $modelPath');
    }

    final vocab = b.llama_model_get_vocab(model);
    return LlamaHandles(
      bindings: b,
      model: model,
      context: nullptr,
      vocab: vocab,
    );
  }

  @override
  Pointer<llama_context> createContext(
    LlamaHandles handles,
    LlamaContextOptions options,
  ) {
    return _createContext(handles.bindings, handles.model, options);
  }

  @override
  void resetContext(
    LlamaHandles handles,
    LlamaContextOptions options,
  ) {
    freeContext(handles);
    handles.context = createContext(handles, options);
    if (handles.context == nullptr) {
      throw StateError('Failed to create context');
    }
  }

  void freeContext(LlamaHandles handles) {
    if (handles.context == nullptr) {
      return;
    }
    handles.bindings.llama_free(handles.context);
    handles.context = nullptr;
  }

  @override
  void dispose(LlamaHandles handles) {
    final b = handles.bindings;
    if (handles.context != nullptr) {
      b.llama_free(handles.context);
    }
    b.llama_free_model(handles.model);
  }

  @override
  List<int> tokenize(
    LlamaHandles handles,
    String text, {
    bool addSpecial = true,
    bool parseSpecial = true,
  }) {
    final bindings = handles.bindings;
    final textUtf8 = text.toNativeUtf8();
    final textPtr = textUtf8.cast<Char>();
    final textLen = textUtf8.length;
    var maxTokens = textLen + 8;
    var tokensPtr = calloc<llama_token>(maxTokens);

    var n = bindings.llama_tokenize(
      handles.vocab,
      textPtr,
      textLen,
      tokensPtr,
      maxTokens,
      addSpecial,
      parseSpecial,
    );
    if (n < 0) {
      calloc.free(tokensPtr);
      maxTokens = -n;
      tokensPtr = calloc<llama_token>(maxTokens);
      n = bindings.llama_tokenize(
        handles.vocab,
        textPtr,
        textLen,
        tokensPtr,
        maxTokens,
        addSpecial,
        parseSpecial,
      );
    }
    calloc.free(textUtf8);

    if (n < 0) {
      calloc.free(tokensPtr);
      throw StateError('Tokenization failed, need ${-n} tokens');
    }

    final result = tokensPtr.asTypedList(n).toList(growable: false);
    calloc.free(tokensPtr);
    return result;
  }

  Uint8List _tokenToPieceBytes(
    LlamaHandles handles,
    int token, {
    int bufferSize = 256,
  }) {
    final b = handles.bindings;
    var buf = calloc<Char>(bufferSize);
    var n = b.llama_token_to_piece(
      handles.vocab,
      token,
      buf,
      bufferSize,
      0,
      true,
    );

    if (n < 0) {
      calloc.free(buf);
      final needed = -n + 1;
      buf = calloc<Char>(needed);
      n = b.llama_token_to_piece(
        handles.vocab,
        token,
        buf,
        needed,
        0,
        true,
      );
    }

    if (n < 0) {
      calloc.free(buf);
      return Uint8List(0);
    }

    final bytes = Uint8List.fromList(buf.cast<Uint8>().asTypedList(n));
    calloc.free(buf);
    return bytes;
  }

  String tokenToPiece(
    LlamaHandles handles,
    int token, {
    int bufferSize = 256,
  }) {
    final bytes = _tokenToPieceBytes(handles, token, bufferSize: bufferSize);
    return bytes.isEmpty ? '' : utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Uint8List tokenToBytes(
    LlamaHandles handles,
    int token, {
    int bufferSize = 256,
  }) {
    return _tokenToPieceBytes(handles, token, bufferSize: bufferSize);
  }

  @override
  void decode(
    LlamaHandles handles,
    Pointer<llama_context> context,
    List<int> tokens,
  ) {
    if (tokens.isEmpty) {
      return;
    }
    final b = handles.bindings;
    final tokenCount = tokens.length;
    final tokenPtr = calloc<llama_token>(tokenCount);
    for (var i = 0; i < tokenCount; i += 1) {
      tokenPtr[i] = tokens[i];
    }

    final batch = b.llama_batch_get_one(tokenPtr, tokenCount);
    final rc = b.llama_decode(context, batch);
    calloc.free(tokenPtr);

    if (rc != 0) {
      throw StateError('llama_decode failed with code $rc');
    }
  }

  @override
  int sampleNext(
    LlamaHandles handles,
    LlamaSamplerChain sampler,
  ) {
    return sampler.sample(handles.context);
  }
}

final class LlamaSamplerChain {
  LlamaSamplerChain(this._bindings, this._sampler);

  factory LlamaSamplerChain.build(
    LlamaBindings bindings,
    SamplingOptions options,
  ) {
    final b = bindings;
    final chainParams = b.llama_sampler_chain_default_params();
    final chain = b.llama_sampler_chain_init(chainParams);

    final topK = options.topK ?? 40;
    final topP = options.topP ?? 0.95;
    final minP = options.minP ?? 0.05;
    final temp = options.temperature ?? 0.7;
    final typicalP = options.typicalP ?? 1.0;
    final penaltyRepeat = options.penaltyRepeat ?? 1.1;
    final penaltyLastN = options.penaltyLastN ?? 64;

    if (topK > 0) {
      b.llama_sampler_chain_add(chain, b.llama_sampler_init_top_k(topK));
    }
    if (topP > 0 && topP < 1.0) {
      b.llama_sampler_chain_add(chain, b.llama_sampler_init_top_p(topP, 1));
    }
    if (minP > 0) {
      b.llama_sampler_chain_add(chain, b.llama_sampler_init_min_p(minP, 1));
    }
    if (typicalP > 0 && typicalP < 1.0) {
      b.llama_sampler_chain_add(
        chain,
        b.llama_sampler_init_typical(typicalP, 1),
      );
    }
    if (penaltyRepeat > 1.0) {
      b.llama_sampler_chain_add(
        chain,
        b.llama_sampler_init_penalties(
          penaltyLastN,
          penaltyRepeat,
          0,
          0,
        ),
      );
    }
    if (temp <= 0) {
      b.llama_sampler_chain_add(chain, b.llama_sampler_init_greedy());
    } else {
      b
        ..llama_sampler_chain_add(chain, b.llama_sampler_init_temp(temp))
        ..llama_sampler_chain_add(
          chain,
          b.llama_sampler_init_dist(options.seed),
        );
    }

    return LlamaSamplerChain(bindings, chain);
  }

  final LlamaBindings _bindings;
  final Pointer<llama_sampler> _sampler;

  int sample(Pointer<llama_context> ctx) {
    return _bindings.llama_sampler_sample(_sampler, ctx, -1);
  }

  void dispose() {
    _bindings.llama_sampler_free(_sampler);
  }
}

Pointer<llama_context> _createContext(
  LlamaBindings b,
  Pointer<llama_model> model,
  LlamaContextOptions contextOptions,
) {
  final ctxParams = b.llama_context_default_params()
    ..n_ctx = contextOptions.contextSize
    ..n_batch = contextOptions.nBatch
    ..n_threads = contextOptions.nThreads
    ..n_threads_batch = contextOptions.nThreadsBatch;
  if (contextOptions.useFlashAttn != null) {
    ctxParams.flash_attn_typeAsInt = contextOptions.useFlashAttn!
        ? llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_ENABLED.value
        : llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_DISABLED.value;
  }

  return b.llama_new_context_with_model(model, ctxParams);
}
