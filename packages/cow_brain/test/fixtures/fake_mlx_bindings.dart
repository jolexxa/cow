// Fake MLX bindings for unit testing.

// C Bindings are special.
// ignore_for_file: avoid_positional_boolean_parameters

import 'dart:ffi';

import 'package:cow_brain/src/adapters/mlx/mlx_bindings.dart';
import 'package:ffi/ffi.dart';
import 'package:mlx_dart/mlx_dart.dart';

final class FakeMlxBindings implements MlxBindings {
  FakeMlxBindings({
    this.initResult = true,
    this.loadModelResult = 1,
    this.modelGetIdResult = 42,
    this.modelFromIdResult = 1,
    this.createContextResult = 10,
    this.resetContextResult = true,
    this.generateBeginResult = true,
    this.isEogResult = false,
    this.tokenizeImpl,
    this.generateNextImpl,
    this.getErrorResult,
  });

  // -- Configurable results --

  bool initResult;
  int loadModelResult;
  int modelGetIdResult;
  int modelFromIdResult;
  int createContextResult;
  bool resetContextResult;
  bool generateBeginResult;
  bool isEogResult;
  String? getErrorResult;

  /// Custom tokenize implementation.
  int Function(
    int modelHandle,
    Pointer<Utf8> text,
    int textLen,
    Pointer<Int32> outTokens,
    int maxTokens,
    bool addSpecial,
  )?
  tokenizeImpl;

  /// Custom generateNext implementation.
  int Function(int contextHandle, Pointer<Utf8> buf, int bufLen)?
  generateNextImpl;

  // -- Call tracking --

  int initCalls = 0;
  int shutdownCalls = 0;
  int getErrorCalls = 0;
  int loadModelCalls = 0;
  int freeModelCalls = 0;
  int modelGetIdCalls = 0;
  int modelFromIdCalls = 0;
  int createContextCalls = 0;
  int freeContextCalls = 0;
  int resetContextCalls = 0;
  int tokenizeCalls = 0;
  int isEogCalls = 0;
  int generateBeginCalls = 0;
  int generateNextCalls = 0;

  // -- Cache tracking --

  int cacheTrimEndResult = 0;
  int cacheTrimFrontResult = 0;
  int cacheTrimEndCalls = 0;
  int cacheTrimFrontCalls = 0;
  int? lastCacheTrimEndN;
  int? lastCacheTrimFrontN;

  // -- Last call arguments --

  List<int>? lastGenerateBeginTokens;
  double? lastTemperature;
  double? lastTopP;
  int? lastTopK;
  double? lastMinP;
  double? lastRepeatPenalty;
  int? lastRepeatWindow;
  int? lastSeed;
  int? lastFreeContextHandle;

  @override
  bool init_() {
    initCalls++;
    return initResult;
  }

  @override
  void shutdown() {
    shutdownCalls++;
  }

  @override
  String? getError() {
    getErrorCalls++;
    return getErrorResult;
  }

  /// If true, invoke the progress callback during loadModel.
  bool invokeProgressCallback = false;

  @override
  int loadModel(
    Pointer<Utf8> path,
    cow_mlx_progress_fn progressCb,
    Pointer<Void> userData,
  ) {
    loadModelCalls++;
    if (invokeProgressCallback && progressCb != nullptr) {
      progressCb.asFunction<bool Function(double, Pointer<Void>)>()(
        0.5,
        userData,
      );
    }
    return loadModelResult;
  }

  @override
  void freeModel(int handle) {
    freeModelCalls++;
  }

  @override
  int modelGetId(int handle) {
    modelGetIdCalls++;
    return modelGetIdResult;
  }

  @override
  int modelFromId(int modelId) {
    modelFromIdCalls++;
    return modelFromIdResult;
  }

  @override
  int createContext(int modelHandle, int maxTokens) {
    createContextCalls++;
    return createContextResult;
  }

  @override
  void freeContext(int contextHandle) {
    freeContextCalls++;
    lastFreeContextHandle = contextHandle;
  }

  @override
  bool resetContext(int contextHandle) {
    resetContextCalls++;
    return resetContextResult;
  }

  @override
  int tokenize(
    int modelHandle,
    Pointer<Utf8> text,
    int textLen,
    Pointer<Int32> outTokens,
    int maxTokens,
    bool addSpecial,
  ) {
    tokenizeCalls++;
    if (tokenizeImpl != null) {
      return tokenizeImpl!(
        modelHandle,
        text,
        textLen,
        outTokens,
        maxTokens,
        addSpecial,
      );
    }
    // Default: write 3 tokens.
    const defaultTokens = [101, 102, 103];
    for (var i = 0; i < defaultTokens.length && i < maxTokens; i++) {
      outTokens[i] = defaultTokens[i];
    }
    return defaultTokens.length;
  }

  @override
  bool isEog(int modelHandle, int token) {
    isEogCalls++;
    return isEogResult;
  }

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
  ) {
    generateBeginCalls++;
    lastGenerateBeginTokens = [
      for (var i = 0; i < tokenCount; i++) tokens[i],
    ];
    lastTemperature = temperature;
    lastTopP = topP;
    lastTopK = topK;
    lastMinP = minP;
    lastRepeatPenalty = repeatPenalty;
    lastRepeatWindow = repeatWindow;
    lastSeed = seed;
    return generateBeginResult;
  }

  @override
  int generateNext(int contextHandle, Pointer<Utf8> buf, int bufLen) {
    generateNextCalls++;
    if (generateNextImpl != null) {
      return generateNextImpl!(contextHandle, buf, bufLen);
    }
    // Default: return -1 (done).
    return -1;
  }

  @override
  int cacheTrimEnd(int contextHandle, int n) {
    cacheTrimEndCalls++;
    lastCacheTrimEndN = n;
    return cacheTrimEndResult;
  }

  @override
  int cacheTrimFront(int contextHandle, int n) {
    cacheTrimFrontCalls++;
    lastCacheTrimFrontN = n;
    return cacheTrimFrontResult;
  }

  // -- Multi-sequence support --

  bool forkContextResult = true;
  int forkContextCalls = 0;
  (int, int)? lastForkContextArgs;

  @override
  bool forkContext(int srcContext, int dstContext) {
    forkContextCalls++;
    lastForkContextArgs = (srcContext, dstContext);
    return forkContextResult;
  }

  // -- Batch generation --

  int batchCreateResult = 1;
  int batchCreateCalls = 0;
  int batchFreeCalls = 0;
  bool batchAddSequenceResult = true;
  int batchAddSequenceCalls = 0;
  int batchPrefillResult = 1;
  int batchPrefillCalls = 0;
  int batchStepResult = 0;
  int batchStepCalls = 0;
  bool batchRemoveSequenceResult = true;
  int batchRemoveSequenceCalls = 0;
  int batchActiveCountResult = 0;
  int batchActiveCountCalls = 0;

  int Function(
    int batchHandle,
    Pointer<Utf8> outTokenBytes,
    int outBufLen,
    Pointer<Int32> outByteLens,
    Pointer<Int32> outSeqIds,
    int maxSeqs,
  )?
  batchStepImpl;

  @override
  int batchCreate(int modelHandle, int maxTokens) {
    batchCreateCalls++;
    return batchCreateResult;
  }

  @override
  void batchFree(int batchHandle) {
    batchFreeCalls++;
  }

  @override
  bool batchAddSequence(
    int batchHandle,
    int seqId,
    Pointer<Int32> tokens,
    int tokenCount,
  ) {
    batchAddSequenceCalls++;
    return batchAddSequenceResult;
  }

  @override
  int batchPrefill(
    int batchHandle,
    double temperature,
    double topP,
    int topK,
    double minP,
    double repeatPenalty,
    int repeatWindow,
    int seed,
  ) {
    batchPrefillCalls++;
    return batchPrefillResult;
  }

  @override
  int batchStep(
    int batchHandle,
    Pointer<Utf8> outTokenBytes,
    int outBufLen,
    Pointer<Int32> outByteLens,
    Pointer<Int32> outSeqIds,
    int maxSeqs,
  ) {
    batchStepCalls++;
    if (batchStepImpl != null) {
      return batchStepImpl!(
        batchHandle,
        outTokenBytes,
        outBufLen,
        outByteLens,
        outSeqIds,
        maxSeqs,
      );
    }
    return batchStepResult;
  }

  @override
  bool batchRemoveSequence(int batchHandle, int seqId) {
    batchRemoveSequenceCalls++;
    return batchRemoveSequenceResult;
  }

  @override
  int batchActiveCount(int batchHandle) {
    batchActiveCountCalls++;
    return batchActiveCountResult;
  }
}
