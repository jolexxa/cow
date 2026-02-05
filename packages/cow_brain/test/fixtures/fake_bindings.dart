// Native llama bindings have odd names and signatures.
// ignore_for_file: avoid_positional_boolean_parameters
// ignore_for_file: non_constant_identifier_names

import 'dart:ffi';

import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:ffi/ffi.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

final class FakeLlamaBindings implements LlamaBindings {
  FakeLlamaBindings({
    this.tokenizeImpl,
    this.tokenToPieceImpl,
    this.decodeImpl,
    this.vocabIsEogImpl,
    this.vocabIsControlImpl,
    this.memorySeqRmImpl,
    this.newContextImpl,
  });

  llama_model_params modelParams = calloc<llama_model_params>().ref;
  llama_context_params contextParams = calloc<llama_context_params>().ref;
  llama_sampler_chain_params chainParams =
      calloc<llama_sampler_chain_params>().ref;
  llama_batch batch = calloc<llama_batch>().ref;

  Pointer<llama_model> modelPtr = Pointer.fromAddress(11);

  int llamaLogSetCalls = 0;
  int ggmlLogSetCalls = 0;
  int backendInitCalls = 0;
  int backendFreeCalls = 0;
  ggml_numa_strategy? lastNumaInit;
  int freeCalls = 0;
  int freeModelCalls = 0;
  int samplerChainAddCalls = 0;
  int samplerFreeCalls = 0;
  int decodeCalls = 0;
  int samplerSampleCalls = 0;
  int samplerSampleResult = 0;

  int tokenizeCalls = 0;
  int tokenToPieceCalls = 0;

  int Function(
    Pointer<llama_vocab>,
    Pointer<Char>,
    int,
    Pointer<llama_token>,
    int,
    bool,
    bool,
  )?
  tokenizeImpl;

  int Function(
    Pointer<llama_vocab>,
    int,
    Pointer<Char>,
    int,
    int,
    bool,
  )?
  tokenToPieceImpl;

  int Function(Pointer<llama_context>, llama_batch)? decodeImpl;

  bool Function(Pointer<llama_vocab>, int)? vocabIsEogImpl;
  bool Function(Pointer<llama_vocab>, int)? vocabIsControlImpl;

  bool Function(llama_memory_t, int, int, int)? memorySeqRmImpl;
  Pointer<llama_context> Function(
    Pointer<llama_model>,
    llama_context_params,
  )?
  newContextImpl;

  (llama_memory_t mem, int seqId, int p0, int p1)? lastMemoryRmArgs;

  Pointer<Char> chatTemplateResult = nullptr;
  int Function(
    Pointer<llama_model>,
    Pointer<Char>,
    Pointer<Char>,
    int,
  )?
  metaValStrImpl;

  llama_memory_t memory = Pointer.fromAddress(101);
  int posMin = 0;
  int posMax = 0;

  @override
  void llama_log_set(
    Pointer<NativeFunction<ggml_log_callbackFunction>> cb,
    Pointer<Void> userData,
  ) {
    llamaLogSetCalls += 1;
  }

  @override
  void ggml_log_set(
    Pointer<NativeFunction<ggml_log_callbackFunction>> cb,
    Pointer<Void> userData,
  ) {
    ggmlLogSetCalls += 1;
  }

  @override
  void llama_backend_init() {
    backendInitCalls += 1;
  }

  @override
  void llama_backend_free() {
    backendFreeCalls += 1;
  }

  @override
  void ggml_backend_load_all_from_path(Pointer<Char> path) {}

  @override
  void llama_numa_init(ggml_numa_strategy numa) {
    lastNumaInit = numa;
  }

  @override
  llama_model_params llama_model_default_params() => modelParams;

  @override
  Pointer<llama_model> llama_load_model_from_file(
    Pointer<Char> path,
    llama_model_params params,
  ) {
    return modelPtr;
  }

  @override
  Pointer<llama_vocab> llama_model_get_vocab(Pointer<llama_model> model) {
    return Pointer.fromAddress(12);
  }

  @override
  llama_context_params llama_context_default_params() => contextParams;

  @override
  Pointer<llama_context> llama_new_context_with_model(
    Pointer<llama_model> model,
    llama_context_params params,
  ) {
    return newContextImpl?.call(model, params) ?? Pointer.fromAddress(13);
  }

  @override
  void llama_free(Pointer<llama_context> ctx) {
    freeCalls += 1;
  }

  @override
  void llama_free_model(Pointer<llama_model> model) {
    freeModelCalls += 1;
  }

  @override
  int llama_tokenize(
    Pointer<llama_vocab> vocab,
    Pointer<Char> text,
    int textLen,
    Pointer<llama_token> tokens,
    int nTokensMax,
    bool addSpecial,
    bool parseSpecial,
  ) {
    tokenizeCalls += 1;
    return tokenizeImpl?.call(
          vocab,
          text,
          textLen,
          tokens,
          nTokensMax,
          addSpecial,
          parseSpecial,
        ) ??
        0;
  }

  @override
  int llama_token_to_piece(
    Pointer<llama_vocab> vocab,
    int token,
    Pointer<Char> buf,
    int length,
    int lstrip,
    bool special,
  ) {
    tokenToPieceCalls += 1;
    return tokenToPieceImpl?.call(vocab, token, buf, length, lstrip, special) ??
        0;
  }

  @override
  llama_batch llama_batch_get_one(Pointer<llama_token> tokens, int nTokens) {
    return batch;
  }

  @override
  int llama_decode(Pointer<llama_context> ctx, llama_batch batch) {
    decodeCalls += 1;
    return decodeImpl?.call(ctx, batch) ?? 0;
  }

  @override
  llama_sampler_chain_params llama_sampler_chain_default_params() =>
      chainParams;

  @override
  Pointer<llama_sampler> llama_sampler_chain_init(
    llama_sampler_chain_params params,
  ) {
    return Pointer.fromAddress(20);
  }

  @override
  void llama_sampler_chain_add(
    Pointer<llama_sampler> chain,
    Pointer<llama_sampler> sampler,
  ) {
    samplerChainAddCalls += 1;
  }

  @override
  Pointer<llama_sampler> llama_sampler_init_top_k(int k) {
    return Pointer.fromAddress(21);
  }

  @override
  Pointer<llama_sampler> llama_sampler_init_top_p(double p, int minKeep) {
    return Pointer.fromAddress(22);
  }

  @override
  Pointer<llama_sampler> llama_sampler_init_min_p(double p, int minKeep) {
    return Pointer.fromAddress(23);
  }

  @override
  Pointer<llama_sampler> llama_sampler_init_typical(double p, int minKeep) {
    return Pointer.fromAddress(24);
  }

  @override
  Pointer<llama_sampler> llama_sampler_init_penalties(
    int penaltyLastN,
    double penaltyRepeat,
    double penaltyFreq,
    double penaltyPresent,
  ) {
    return Pointer.fromAddress(25);
  }

  @override
  Pointer<llama_sampler> llama_sampler_init_greedy() {
    return Pointer.fromAddress(26);
  }

  @override
  Pointer<llama_sampler> llama_sampler_init_temp(double temp) {
    return Pointer.fromAddress(27);
  }

  @override
  Pointer<llama_sampler> llama_sampler_init_dist(int seed) {
    return Pointer.fromAddress(28);
  }

  @override
  int llama_sampler_sample(
    Pointer<llama_sampler> sampler,
    Pointer<llama_context> ctx,
    int idx,
  ) {
    samplerSampleCalls += 1;
    return samplerSampleResult;
  }

  @override
  void llama_sampler_free(Pointer<llama_sampler> sampler) {
    samplerFreeCalls += 1;
  }

  @override
  bool llama_vocab_is_eog(Pointer<llama_vocab> vocab, int token) {
    return vocabIsEogImpl?.call(vocab, token) ?? false;
  }

  @override
  bool llama_vocab_is_control(Pointer<llama_vocab> vocab, int token) {
    return vocabIsControlImpl?.call(vocab, token) ?? false;
  }

  @override
  llama_memory_t llama_get_memory(Pointer<llama_context> ctx) {
    return memory;
  }

  @override
  int llama_memory_seq_pos_min(llama_memory_t mem, int seqId) {
    return posMin;
  }

  @override
  int llama_memory_seq_pos_max(llama_memory_t mem, int seqId) {
    return posMax;
  }

  @override
  bool llama_memory_seq_rm(
    llama_memory_t mem,
    int seqId,
    int p0,
    int p1,
  ) {
    lastMemoryRmArgs = (mem, seqId, p0, p1);
    return memorySeqRmImpl?.call(mem, seqId, p0, p1) ?? true;
  }

  @override
  Pointer<Char> llama_model_chat_template(
    Pointer<llama_model> model,
    Pointer<Char> name,
  ) {
    return chatTemplateResult;
  }

  @override
  int llama_model_meta_val_str(
    Pointer<llama_model> model,
    Pointer<Char> key,
    Pointer<Char> buf,
    int bufSize,
  ) {
    return metaValStrImpl?.call(model, key, buf, bufSize) ?? -1;
  }
}
