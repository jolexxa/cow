// Native bindings adapter for llama.cpp.
// Native bindings have weird names and weird signatures.
// ignore_for_file: avoid_positional_boolean_parameters
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs

import 'dart:ffi';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';

abstract class LlamaBindings {
  void llama_log_set(
    Pointer<NativeFunction<ggml_log_callbackFunction>> cb,
    Pointer<Void> userData,
  );

  void ggml_log_set(
    Pointer<NativeFunction<ggml_log_callbackFunction>> cb,
    Pointer<Void> userData,
  );

  void llama_backend_init();
  void llama_backend_free();
  void ggml_backend_load_all_from_path(Pointer<Char> path);
  void llama_numa_init(ggml_numa_strategy numa);

  llama_model_params llama_model_default_params();
  Pointer<llama_model> llama_load_model_from_file(
    Pointer<Char> path,
    llama_model_params params,
  );
  Pointer<llama_vocab> llama_model_get_vocab(Pointer<llama_model> model);

  llama_context_params llama_context_default_params();
  Pointer<llama_context> llama_new_context_with_model(
    Pointer<llama_model> model,
    llama_context_params params,
  );

  void llama_free(Pointer<llama_context> ctx);
  void llama_free_model(Pointer<llama_model> model);

  int llama_tokenize(
    Pointer<llama_vocab> vocab,
    Pointer<Char> text,
    int textLen,
    Pointer<llama_token> tokens,
    int nTokensMax,
    bool addSpecial,
    bool parseSpecial,
  );

  int llama_token_to_piece(
    Pointer<llama_vocab> vocab,
    int token,
    Pointer<Char> buf,
    int length,
    int lstrip,
    bool special,
  );

  llama_batch llama_batch_get_one(
    Pointer<llama_token> tokens,
    int nTokens,
  );

  int llama_decode(Pointer<llama_context> ctx, llama_batch batch);

  llama_sampler_chain_params llama_sampler_chain_default_params();
  Pointer<llama_sampler> llama_sampler_chain_init(
    llama_sampler_chain_params params,
  );
  void llama_sampler_chain_add(
    Pointer<llama_sampler> chain,
    Pointer<llama_sampler> sampler,
  );
  Pointer<llama_sampler> llama_sampler_init_top_k(int k);
  Pointer<llama_sampler> llama_sampler_init_top_p(double p, int minKeep);
  Pointer<llama_sampler> llama_sampler_init_min_p(double p, int minKeep);
  Pointer<llama_sampler> llama_sampler_init_typical(double p, int minKeep);
  Pointer<llama_sampler> llama_sampler_init_penalties(
    int penaltyLastN,
    double penaltyRepeat,
    double penaltyFreq,
    double penaltyPresent,
  );
  Pointer<llama_sampler> llama_sampler_init_greedy();
  Pointer<llama_sampler> llama_sampler_init_temp(double temp);
  Pointer<llama_sampler> llama_sampler_init_dist(int seed);
  int llama_sampler_sample(
    Pointer<llama_sampler> sampler,
    Pointer<llama_context> ctx,
    int idx,
  );
  void llama_sampler_free(Pointer<llama_sampler> sampler);

  bool llama_vocab_is_eog(Pointer<llama_vocab> vocab, int token);
  bool llama_vocab_is_control(Pointer<llama_vocab> vocab, int token);

  llama_memory_t llama_get_memory(Pointer<llama_context> ctx);
  int llama_memory_seq_pos_min(llama_memory_t mem, int seqId);
  int llama_memory_seq_pos_max(llama_memory_t mem, int seqId);
  bool llama_memory_seq_rm(
    llama_memory_t mem,
    int seqId,
    int p0,
    int p1,
  );

  Pointer<Char> llama_model_chat_template(
    Pointer<llama_model> model,
    Pointer<Char> name,
  );

  int llama_model_meta_val_str(
    Pointer<llama_model> model,
    Pointer<Char> key,
    Pointer<Char> buf,
    int bufSize,
  );
}

final class LlamaBindingsAdapter implements LlamaBindings {
  LlamaBindingsAdapter(this._bindings);

  final LlamaCppBindings _bindings;

  @override
  void llama_log_set(
    Pointer<NativeFunction<ggml_log_callbackFunction>> cb,
    Pointer<Void> userData,
  ) => _bindings.llama_log_set(cb, userData);

  @override
  void ggml_log_set(
    Pointer<NativeFunction<ggml_log_callbackFunction>> cb,
    Pointer<Void> userData,
  ) => _bindings.ggml_log_set(cb, userData);

  @override
  void llama_backend_init() => _bindings.llama_backend_init();

  @override
  void llama_backend_free() => _bindings.llama_backend_free();

  @override
  void ggml_backend_load_all_from_path(Pointer<Char> path) =>
      _bindings.ggml_backend_load_all_from_path(path);

  @override
  void llama_numa_init(ggml_numa_strategy numa) =>
      _bindings.llama_numa_init(numa);

  @override
  llama_model_params llama_model_default_params() =>
      _bindings.llama_model_default_params();

  @override
  Pointer<llama_model> llama_load_model_from_file(
    Pointer<Char> path,
    llama_model_params params,
  ) => _bindings.llama_load_model_from_file(path, params);

  @override
  Pointer<llama_vocab> llama_model_get_vocab(Pointer<llama_model> model) =>
      _bindings.llama_model_get_vocab(model);

  @override
  llama_context_params llama_context_default_params() =>
      _bindings.llama_context_default_params();

  @override
  Pointer<llama_context> llama_new_context_with_model(
    Pointer<llama_model> model,
    llama_context_params params,
  ) => _bindings.llama_new_context_with_model(model, params);

  @override
  void llama_free(Pointer<llama_context> ctx) => _bindings.llama_free(ctx);

  @override
  void llama_free_model(Pointer<llama_model> model) =>
      _bindings.llama_free_model(model);

  @override
  int llama_tokenize(
    Pointer<llama_vocab> vocab,
    Pointer<Char> text,
    int textLen,
    Pointer<llama_token> tokens,
    int nTokensMax,
    bool addSpecial,
    bool parseSpecial,
  ) => _bindings.llama_tokenize(
    vocab,
    text,
    textLen,
    tokens,
    nTokensMax,
    addSpecial,
    parseSpecial,
  );

  @override
  int llama_token_to_piece(
    Pointer<llama_vocab> vocab,
    int token,
    Pointer<Char> buf,
    int length,
    int lstrip,
    bool special,
  ) => _bindings.llama_token_to_piece(
    vocab,
    token,
    buf,
    length,
    lstrip,
    special,
  );

  @override
  llama_batch llama_batch_get_one(Pointer<llama_token> tokens, int nTokens) =>
      _bindings.llama_batch_get_one(tokens, nTokens);

  @override
  int llama_decode(Pointer<llama_context> ctx, llama_batch batch) =>
      _bindings.llama_decode(ctx, batch);

  @override
  llama_sampler_chain_params llama_sampler_chain_default_params() =>
      _bindings.llama_sampler_chain_default_params();

  @override
  Pointer<llama_sampler> llama_sampler_chain_init(
    llama_sampler_chain_params params,
  ) => _bindings.llama_sampler_chain_init(params);

  @override
  void llama_sampler_chain_add(
    Pointer<llama_sampler> chain,
    Pointer<llama_sampler> sampler,
  ) => _bindings.llama_sampler_chain_add(chain, sampler);

  @override
  Pointer<llama_sampler> llama_sampler_init_top_k(int k) =>
      _bindings.llama_sampler_init_top_k(k);

  @override
  Pointer<llama_sampler> llama_sampler_init_top_p(double p, int minKeep) =>
      _bindings.llama_sampler_init_top_p(p, minKeep);

  @override
  Pointer<llama_sampler> llama_sampler_init_min_p(double p, int minKeep) =>
      _bindings.llama_sampler_init_min_p(p, minKeep);

  @override
  Pointer<llama_sampler> llama_sampler_init_typical(double p, int minKeep) =>
      _bindings.llama_sampler_init_typical(p, minKeep);

  @override
  Pointer<llama_sampler> llama_sampler_init_penalties(
    int penaltyLastN,
    double penaltyRepeat,
    double penaltyFreq,
    double penaltyPresent,
  ) => _bindings.llama_sampler_init_penalties(
    penaltyLastN,
    penaltyRepeat,
    penaltyFreq,
    penaltyPresent,
  );

  @override
  Pointer<llama_sampler> llama_sampler_init_greedy() =>
      _bindings.llama_sampler_init_greedy();

  @override
  Pointer<llama_sampler> llama_sampler_init_temp(double temp) =>
      _bindings.llama_sampler_init_temp(temp);

  @override
  Pointer<llama_sampler> llama_sampler_init_dist(int seed) =>
      _bindings.llama_sampler_init_dist(seed);

  @override
  int llama_sampler_sample(
    Pointer<llama_sampler> sampler,
    Pointer<llama_context> ctx,
    int idx,
  ) => _bindings.llama_sampler_sample(sampler, ctx, idx);

  @override
  void llama_sampler_free(Pointer<llama_sampler> sampler) =>
      _bindings.llama_sampler_free(sampler);

  @override
  bool llama_vocab_is_eog(Pointer<llama_vocab> vocab, int token) =>
      _bindings.llama_vocab_is_eog(vocab, token);

  @override
  bool llama_vocab_is_control(Pointer<llama_vocab> vocab, int token) =>
      _bindings.llama_vocab_is_control(vocab, token);

  @override
  llama_memory_t llama_get_memory(Pointer<llama_context> ctx) =>
      _bindings.llama_get_memory(ctx);

  @override
  int llama_memory_seq_pos_min(llama_memory_t mem, int seqId) =>
      _bindings.llama_memory_seq_pos_min(mem, seqId);

  @override
  int llama_memory_seq_pos_max(llama_memory_t mem, int seqId) =>
      _bindings.llama_memory_seq_pos_max(mem, seqId);

  @override
  bool llama_memory_seq_rm(
    llama_memory_t mem,
    int seqId,
    int p0,
    int p1,
  ) => _bindings.llama_memory_seq_rm(mem, seqId, p0, p1);

  @override
  Pointer<Char> llama_model_chat_template(
    Pointer<llama_model> model,
    Pointer<Char> name,
  ) => _bindings.llama_model_chat_template(model, name);

  @override
  int llama_model_meta_val_str(
    Pointer<llama_model> model,
    Pointer<Char> key,
    Pointer<Char> buf,
    int bufSize,
  ) => _bindings.llama_model_meta_val_str(model, key, buf, bufSize);
}

final class LlamaBindingsLoader {
  static LlamaBindings open({
    required String libraryPath,
  }) {
    final dylib = DynamicLibrary.open(libraryPath);
    return LlamaBindingsAdapter(LlamaCppBindings(dylib));
  }
}
