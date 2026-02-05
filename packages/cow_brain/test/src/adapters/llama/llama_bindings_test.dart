// Causes analyzer issues.
// Native bindings have odd names and signatures.
// ignore_for_file: non_constant_identifier_names, cascade_invocations

import 'dart:ffi';
import 'dart:io';

import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:ffi/ffi.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:test/test.dart';

void main() {
  group('LlamaBindingsAdapter', () {
    test('forwards calls to the underlying bindings', () {
      final fake = FakeCppBindings();
      final adapter = LlamaBindingsAdapter(fake);

      adapter.llama_log_set(nullptr, nullptr);
      adapter.ggml_log_set(nullptr, nullptr);
      adapter.llama_backend_init();
      adapter.llama_backend_free();
      adapter.ggml_backend_load_all_from_path(Pointer.fromAddress(10));
      adapter.llama_numa_init(ggml_numa_strategy.GGML_NUMA_STRATEGY_DISTRIBUTE);
      expect(fake.logCalls, 2);
      expect(fake.backendInitCalls, 1);
      expect(fake.backendFreeCalls, 1);
      expect(fake.backendLoadCalls, 1);
      expect(
        fake.lastNuma?.value,
        ggml_numa_strategy.GGML_NUMA_STRATEGY_DISTRIBUTE.value,
      );

      expect(adapter.llama_model_default_params(), same(fake.modelParams));
      expect(
        adapter.llama_load_model_from_file(
          Pointer.fromAddress(1),
          fake.modelParams,
        ),
        same(fake.modelPtr),
      );
      expect(
        adapter.llama_model_get_vocab(Pointer.fromAddress(2)),
        same(fake.vocabPtr),
      );

      expect(
        adapter.llama_context_default_params(),
        same(fake.contextParams),
      );
      expect(
        adapter.llama_new_context_with_model(
          Pointer.fromAddress(3),
          fake.contextParams,
        ),
        same(fake.contextPtr),
      );

      adapter.llama_free(Pointer.fromAddress(4));
      adapter.llama_free_model(Pointer.fromAddress(5));
      expect(fake.freeCalls, 1);
      expect(fake.freeModelCalls, 1);

      final tokens = calloc<llama_token>(2);
      final tokenizeRc = adapter.llama_tokenize(
        Pointer.fromAddress(6),
        Pointer.fromAddress(7),
        3,
        tokens,
        2,
        true,
        false,
      );
      expect(tokenizeRc, 2);
      expect(fake.tokenizeCalls, 1);

      final buf = calloc<Char>(8);
      final tokenToPieceRc = adapter.llama_token_to_piece(
        Pointer.fromAddress(8),
        5,
        buf,
        8,
        0,
        true,
      );
      expect(tokenToPieceRc, 1);
      expect(fake.tokenToPieceCalls, 1);

      expect(
        adapter.llama_batch_get_one(tokens, 2),
        same(fake.batch),
      );
      expect(
        adapter.llama_decode(Pointer.fromAddress(9), fake.batch),
        0,
      );

      expect(
        adapter.llama_sampler_chain_default_params(),
        same(fake.chainParams),
      );
      expect(
        adapter.llama_sampler_chain_init(fake.chainParams),
        same(fake.chainPtr),
      );
      adapter.llama_sampler_chain_add(fake.chainPtr, fake.samplerPtr);
      expect(fake.chainAddCalls, 1);

      expect(
        adapter.llama_sampler_init_top_k(8),
        same(fake.samplerPtr),
      );
      expect(
        adapter.llama_sampler_init_top_p(0.5, 1),
        same(fake.samplerPtr),
      );
      expect(
        adapter.llama_sampler_init_min_p(0.3, 1),
        same(fake.samplerPtr),
      );
      expect(
        adapter.llama_sampler_init_typical(0.9, 1),
        same(fake.samplerPtr),
      );
      expect(
        adapter.llama_sampler_init_penalties(32, 1.1, 0, 0),
        same(fake.samplerPtr),
      );
      expect(adapter.llama_sampler_init_greedy(), same(fake.samplerPtr));
      expect(adapter.llama_sampler_init_temp(0.7), same(fake.samplerPtr));
      expect(adapter.llama_sampler_init_dist(1), same(fake.samplerPtr));
      expect(
        adapter.llama_sampler_sample(fake.samplerPtr, fake.contextPtr, -1),
        7,
      );
      adapter.llama_sampler_free(fake.samplerPtr);
      expect(fake.samplerFreeCalls, 1);

      expect(adapter.llama_vocab_is_eog(fake.vocabPtr, 2), isTrue);
      expect(adapter.llama_vocab_is_control(fake.vocabPtr, 3), isFalse);

      expect(
        adapter.llama_get_memory(fake.contextPtr),
        same(fake.memoryPtr),
      );
      expect(adapter.llama_memory_seq_pos_min(fake.memoryPtr, 0), 10);
      expect(adapter.llama_memory_seq_pos_max(fake.memoryPtr, 0), 20);
      expect(adapter.llama_memory_seq_rm(fake.memoryPtr, 0, 0, 4), isTrue);

      expect(
        adapter.llama_model_chat_template(fake.modelPtr, nullptr.cast()),
        same(fake.chatTemplatePtr),
      );
      expect(fake.chatTemplateCalls, 1);

      final metaBuf = calloc<Char>(64);
      final metaKey = 'general.name'.toNativeUtf8().cast<Char>();
      expect(
        adapter.llama_model_meta_val_str(
          fake.modelPtr,
          metaKey,
          metaBuf,
          64,
        ),
        42,
      );
      expect(fake.metaValStrCalls, 1);
      calloc.free(metaBuf);
      malloc.free(metaKey);

      calloc.free(tokens);
      calloc.free(buf);
      fake.dispose();
    });
  });

  group('LlamaBindingsLoader', () {
    test('opens a dynamic library via the loader', () {
      final path = switch (Platform.operatingSystem) {
        'macos' => '/usr/lib/libSystem.B.dylib',
        'linux' => 'libc.so.6',
        'windows' => 'kernel32.dll',
        _ => null,
      };
      if (path == null) {
        return;
      }

      final bindings = LlamaBindingsLoader.open(libraryPath: path);
      expect(bindings, isA<LlamaBindingsAdapter>());
    });
  });
}

final class FakeCppBindings extends LlamaCppBindings {
  FakeCppBindings() : super.fromLookup(_lookup);

  static Pointer<T> _lookup<T extends NativeType>(String _) =>
      Pointer.fromAddress(0);

  final Pointer<llama_model_params> modelParamsPtr =
      calloc<llama_model_params>();
  final Pointer<llama_context_params> contextParamsPtr =
      calloc<llama_context_params>();
  final Pointer<llama_sampler_chain_params> chainParamsPtr =
      calloc<llama_sampler_chain_params>();
  final Pointer<llama_batch> batchPtr = calloc<llama_batch>();

  late final llama_model_params modelParams = modelParamsPtr.ref;
  late final llama_context_params contextParams = contextParamsPtr.ref;
  late final llama_sampler_chain_params chainParams = chainParamsPtr.ref;
  late final llama_batch batch = batchPtr.ref;

  final Pointer<llama_model> modelPtr = Pointer.fromAddress(1);
  final Pointer<llama_vocab> vocabPtr = Pointer.fromAddress(2);
  final Pointer<llama_context> contextPtr = Pointer.fromAddress(3);
  final Pointer<llama_sampler> chainPtr = Pointer.fromAddress(4);
  final Pointer<llama_sampler> samplerPtr = Pointer.fromAddress(5);
  final llama_memory_t memoryPtr = Pointer.fromAddress(6);

  int logCalls = 0;
  int backendInitCalls = 0;
  int backendFreeCalls = 0;
  int backendLoadCalls = 0;
  int freeCalls = 0;
  int freeModelCalls = 0;
  int tokenizeCalls = 0;
  int tokenToPieceCalls = 0;
  int chainAddCalls = 0;
  int samplerFreeCalls = 0;
  int chatTemplateCalls = 0;
  int metaValStrCalls = 0;
  final Pointer<Char> chatTemplatePtr = Pointer.fromAddress(99);
  ggml_numa_strategy? lastNuma;

  void dispose() {
    calloc.free(modelParamsPtr);
    calloc.free(contextParamsPtr);
    calloc.free(chainParamsPtr);
    calloc.free(batchPtr);
  }

  @override
  void llama_log_set(
    Pointer<NativeFunction<ggml_log_callbackFunction>> cb,
    Pointer<Void> userData,
  ) {
    logCalls += 1;
  }

  @override
  void ggml_log_set(
    Pointer<NativeFunction<ggml_log_callbackFunction>> cb,
    Pointer<Void> userData,
  ) {
    logCalls += 1;
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
  void ggml_backend_load_all_from_path(Pointer<Char> path) {
    backendLoadCalls += 1;
  }

  @override
  void llama_numa_init(ggml_numa_strategy numa) {
    lastNuma = numa;
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
    return vocabPtr;
  }

  @override
  llama_context_params llama_context_default_params() => contextParams;

  @override
  Pointer<llama_context> llama_new_context_with_model(
    Pointer<llama_model> model,
    llama_context_params params,
  ) {
    return contextPtr;
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
    return 2;
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
    return 1;
  }

  @override
  llama_batch llama_batch_get_one(Pointer<llama_token> tokens, int nTokens) =>
      batch;

  @override
  int llama_decode(Pointer<llama_context> ctx, llama_batch batch) => 0;

  @override
  llama_sampler_chain_params llama_sampler_chain_default_params() =>
      chainParams;

  @override
  Pointer<llama_sampler> llama_sampler_chain_init(
    llama_sampler_chain_params params,
  ) {
    return chainPtr;
  }

  @override
  void llama_sampler_chain_add(
    Pointer<llama_sampler> chain,
    Pointer<llama_sampler> sampler,
  ) {
    chainAddCalls += 1;
  }

  @override
  Pointer<llama_sampler> llama_sampler_init_top_k(int k) => samplerPtr;

  @override
  Pointer<llama_sampler> llama_sampler_init_top_p(double p, int minKeep) =>
      samplerPtr;

  @override
  Pointer<llama_sampler> llama_sampler_init_min_p(double p, int minKeep) =>
      samplerPtr;

  @override
  Pointer<llama_sampler> llama_sampler_init_typical(double p, int minKeep) =>
      samplerPtr;

  @override
  Pointer<llama_sampler> llama_sampler_init_penalties(
    int penaltyLastN,
    double penaltyRepeat,
    double penaltyFreq,
    double penaltyPresent,
  ) => samplerPtr;

  @override
  Pointer<llama_sampler> llama_sampler_init_greedy() => samplerPtr;

  @override
  Pointer<llama_sampler> llama_sampler_init_temp(double temp) => samplerPtr;

  @override
  Pointer<llama_sampler> llama_sampler_init_dist(int seed) => samplerPtr;

  @override
  int llama_sampler_sample(
    Pointer<llama_sampler> sampler,
    Pointer<llama_context> ctx,
    int idx,
  ) {
    return 7;
  }

  @override
  void llama_sampler_free(Pointer<llama_sampler> sampler) {
    samplerFreeCalls += 1;
  }

  @override
  bool llama_vocab_is_eog(Pointer<llama_vocab> vocab, int token) => true;

  @override
  bool llama_vocab_is_control(Pointer<llama_vocab> vocab, int token) => false;

  @override
  llama_memory_t llama_get_memory(Pointer<llama_context> ctx) => memoryPtr;

  @override
  int llama_memory_seq_pos_min(llama_memory_t mem, int seqId) => 10;

  @override
  int llama_memory_seq_pos_max(llama_memory_t mem, int seqId) => 20;

  @override
  bool llama_memory_seq_rm(llama_memory_t mem, int seqId, int p0, int p1) =>
      true;

  @override
  Pointer<Char> llama_model_chat_template(
    Pointer<llama_model> model,
    Pointer<Char> name,
  ) {
    chatTemplateCalls += 1;
    return chatTemplatePtr;
  }

  @override
  int llama_model_meta_val_str(
    Pointer<llama_model> model,
    Pointer<Char> key,
    Pointer<Char> buf,
    int bufSize,
  ) {
    metaValStrCalls += 1;
    return 42;
  }
}
