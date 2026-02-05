// Native bindings have weird names.
// ignore_for_file: non_constant_identifier_names

import 'dart:ffi';
import 'dart:typed_data';

import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:cow_brain/src/agent/agent.dart';
import 'package:cow_brain/src/context/context.dart';
import 'package:cow_brain/src/core/core.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/tools/tools.dart';
import 'package:ffi/ffi.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_bindings.dart';

void main() {
  group('createAgentWithLlama', () {
    test('wires tools into the prompt and runs a two-step tool turn', () async {
      final runtime = ScriptedLlamaRuntime([
        '<tool_call>{"id":"1","name":"search","arguments":{"q":"cow"}}</tool_call>',
        'Done.',
      ]);

      final tools = ToolRegistry()
        ..register(
          const ToolDefinition(
            name: 'search',
            description: 'Search the web',
            parameters: {},
          ),
          (args) => 'Result for ${args['q']}',
        );

      final bundle = createAgentWithLlama(
        runtime: runtime,
        tools: tools,
        conversation: Conversation.initial(),
        contextSize: 4096,
        maxOutputTokens: 256,
        temperature: 0.7,
        profile: LlamaProfiles.qwen3,
        safetyMarginTokens: 64,
      );

      final conversation = bundle.conversation..addUser('Find cow facts');
      final events = await bundle.agent.runTurn(conversation).toList();

      expect(runtime.prompts.first, contains('<tools>'));
      expect(runtime.prompts.first, contains('"name":"search"'));
      expect(events.whereType<AgentToolResult>(), hasLength(1));
      expect(events.last, isA<AgentTurnFinished>());
      expect(
        (events.last as AgentTurnFinished).finishReason,
        FinishReason.stop,
      );
      expect(conversation.messages.last.content, 'Done.');
    });

    test('uses provided tools and conversation', () {
      final runtime = ScriptedLlamaRuntime(const []);
      final tools = ToolRegistry();
      final convo = Conversation.initial();

      final bundle = createAgentWithLlama(
        runtime: runtime,
        tools: tools,
        conversation: convo,
        contextSize: 64,
        maxOutputTokens: 16,
        temperature: 0.7,
        profile: LlamaProfiles.qwen3,
        safetyMarginTokens: 64,
      );

      expect(bundle.tools, same(tools));
      expect(bundle.conversation, same(convo));
    });

    test('accepts empty tools and a fresh conversation', () {
      final runtime = ScriptedLlamaRuntime(const []);
      final tools = ToolRegistry();
      final convo = Conversation.initial();

      final bundle = _createAgentWithLlama(
        runtime: runtime,
        tools: tools,
        conversation: convo,
      );

      expect(bundle.tools, same(tools));
      expect(bundle.conversation, same(convo));
    });
  });

  group('createAgent', () {
    test('throws when contextSize exceeds the runtime context size', () {
      expect(
        () => createAgent(
          modelPointer: 1,
          runtimeOptions: _runtimeOptions,
          contextSize: 256,
          maxOutputTokens: 64,
          temperature: 0.7,
          profileId: LlamaProfileId.qwen3,
          tools: ToolRegistry(),
          conversation: Conversation.initial(),
          safetyMarginTokens: 64,
          runtimeFactory: ({required int modelPointer, required options}) =>
              LlamaCppRuntime(
                modelPointer: modelPointer,
                options: options,
                client: FakeLlamaClient(),
                bindings: _NoopBindings(),
              ),
        ),
        throwsArgumentError,
      );
    });

    test('propagates provided tools and conversation', () {
      final tools = ToolRegistry();
      final convo = Conversation.initial();

      final bundle = _createAgent(
        tools: tools,
        conversation: convo,
      );

      expect(bundle.tools, same(tools));
      expect(bundle.conversation, same(convo));
      expect(bundle.runtime, isA<LlamaCppRuntime>());
    });

    test('creates a runtime via the provided factory', () {
      final bundle = _createAgent(
        tools: ToolRegistry(),
        conversation: Conversation.initial(),
      );
      expect(bundle.runtime, isA<LlamaCppRuntime>());
    });

    test('auto profileId falls back to qwen3 when no template', () {
      final bindings = FakeLlamaBindings();
      final bundle = createAgent(
        modelPointer: 1,
        runtimeOptions: _runtimeOptions,
        profileId: LlamaProfileId.auto,
        tools: ToolRegistry(),
        conversation: Conversation.initial(),
        contextSize: 128,
        maxOutputTokens: 32,
        temperature: 0.7,
        safetyMarginTokens: 64,
        runtimeFactory: ({required int modelPointer, required options}) =>
            LlamaCppRuntime(
              modelPointer: modelPointer,
              options: options,
              client: FakeLlamaClient(bindings: bindings),
              bindings: bindings,
            ),
      );

      // No chat template (nullptr) → falls back to qwen3.
      expect(bundle.llm.profile.formatter, isA<Qwen3PromptFormatter>());
      bundle.runtime.dispose();
    });
  });

  group('detectProfileFromRuntime', () {
    test('returns fallback when chat template is null', () {
      final bindings = FakeLlamaBindings();
      // Default chatTemplateResult is nullptr → chatTemplate returns null.
      final runtime = LlamaCppRuntime(
        modelPointer: 1,
        options: _runtimeOptions,
        client: FakeLlamaClient(bindings: bindings),
        bindings: bindings,
      );

      final profile = detectProfileFromRuntime(
        runtime,
        fallback: LlamaProfiles.qwen3,
      );
      expect(profile.formatter, isA<Qwen3PromptFormatter>());
      runtime.dispose();
    });

    test('detects profile from chat template when present', () {
      final bindings = FakeLlamaBindings()
        ..chatTemplateResult = '<|im_start|>system\n{content}<|im_end|>'
            .toNativeUtf8()
            .cast<Char>();
      final runtime = LlamaCppRuntime(
        modelPointer: 1,
        options: _runtimeOptions,
        client: FakeLlamaClient(bindings: bindings),
        bindings: bindings,
      );

      final profile = detectProfileFromRuntime(
        runtime,
        fallback: LlamaProfiles.qwen25,
      );
      // Template contains <|im_start|> → detected as qwen3.
      expect(profile.formatter, isA<Qwen3PromptFormatter>());
      runtime.dispose();
    });
  });
}

const _runtimeOptions = LlamaRuntimeOptions(
  modelPath: 'model',
  libraryPath: '/tmp/libllama.so',
  contextOptions: LlamaContextOptions(
    contextSize: 128,
    nBatch: 1,
    nThreads: 1,
    nThreadsBatch: 1,
  ),
);

({
  AgentLoop agent,
  Conversation conversation,
  LlamaAdapter llm,
  ToolRegistry tools,
  ContextManager context,
})
_createAgentWithLlama({
  required LlamaRuntime runtime,
  required ToolRegistry tools,
  required Conversation conversation,
  int contextSize = 64,
  int maxOutputTokens = 16,
}) {
  return createAgentWithLlama(
    runtime: runtime,
    tools: tools,
    conversation: conversation,
    contextSize: contextSize,
    maxOutputTokens: maxOutputTokens,
    temperature: 0.7,
    profile: LlamaProfiles.qwen3,
    safetyMarginTokens: 64,
  );
}

({
  AgentLoop agent,
  Conversation conversation,
  LlamaAdapter llm,
  ToolRegistry tools,
  ContextManager context,
  LlamaCppRuntime runtime,
})
_createAgent({
  required ToolRegistry tools,
  required Conversation conversation,
  int contextSize = 128,
  int maxOutputTokens = 32,
  LlamaProfileId profileId = LlamaProfileId.qwen3,
}) {
  return createAgent(
    modelPointer: 1,
    runtimeOptions: _runtimeOptions,
    tools: tools,
    conversation: conversation,
    profileId: profileId,
    contextSize: contextSize,
    maxOutputTokens: maxOutputTokens,
    temperature: 0.7,
    safetyMarginTokens: 64,
    runtimeFactory: ({required int modelPointer, required options}) =>
        LlamaCppRuntime(
          modelPointer: modelPointer,
          options: options,
          client: FakeLlamaClient(),
          bindings: _NoopBindings(),
        ),
  );
}

final class ScriptedLlamaRuntime implements LlamaRuntime {
  ScriptedLlamaRuntime(this._outputs);

  final List<String> _outputs;
  final List<String> prompts = <String>[];
  var _index = 0;
  String lastPrompt = '';

  @override
  int countTokens(String prompt, {required bool addBos}) {
    return prompt.length + (addBos ? 1 : 0);
  }

  @override
  Stream<LlamaStreamChunk> generate({
    required String prompt,
    required List<String> stopSequences,
    required bool addBos,
    required bool requiresReset,
    required int reusePrefixMessageCount,
  }) async* {
    prompts.add(prompt);
    lastPrompt = prompt;
    if (_index >= _outputs.length) {
      return;
    }
    final output = _outputs[_index];
    _index += 1;
    yield LlamaStreamChunk(text: output, tokenCountDelta: 0);
  }
}

final class FakeLlamaClient implements LlamaClientApi {
  FakeLlamaClient({LlamaBindings? bindings}) : _bindings = bindings;

  final LlamaBindings? _bindings;

  @override
  LlamaHandles loadModel({
    required String modelPath,
    required LlamaModelOptions modelOptions,
    ModelLoadProgressCallback? onProgress,
  }) {
    return LlamaHandles(
      bindings: _bindings ?? _NoopBindings(),
      model: Pointer.fromAddress(1),
      context: Pointer.fromAddress(2),
      vocab: Pointer.fromAddress(3),
    );
  }

  @override
  List<int> tokenize(
    LlamaHandles handles,
    String text, {
    bool addSpecial = true,
    bool parseSpecial = true,
  }) {
    return <int>[1, 2, 3];
  }

  @override
  Pointer<llama_context> createContext(
    LlamaHandles handles,
    LlamaContextOptions options,
  ) {
    return Pointer.fromAddress(2);
  }

  @override
  void decode(
    LlamaHandles handles,
    Pointer<llama_context> context,
    List<int> tokens,
  ) {}

  @override
  void dispose(LlamaHandles handles) {}

  @override
  int sampleNext(
    LlamaHandles handles,
    LlamaSamplerChain sampler,
  ) {
    return 0;
  }

  @override
  Uint8List tokenToBytes(
    LlamaHandles handles,
    int token, {
    int bufferSize = 256,
  }) {
    return Uint8List(0);
  }

  @override
  void resetContext(
    LlamaHandles handles,
    LlamaContextOptions options,
  ) {}
}

final class _NoopBindings implements LlamaBindings {
  @override
  llama_batch llama_batch_get_one(Pointer<llama_token> tokens, int nTokens) {
    throw UnimplementedError();
  }

  @override
  void ggml_log_set(
    Pointer<NativeFunction<ggml_log_callbackFunction>> cb,
    Pointer<Void> userData,
  ) {}

  @override
  void llama_backend_free() {}

  @override
  void llama_backend_init() {}

  @override
  void ggml_backend_load_all_from_path(Pointer<Char> path) {}

  @override
  void llama_free(Pointer<llama_context> ctx) {}

  @override
  void llama_free_model(Pointer<llama_model> model) {}

  @override
  llama_memory_t llama_get_memory(Pointer<llama_context> ctx) {
    throw UnimplementedError();
  }

  @override
  llama_context_params llama_context_default_params() {
    throw UnimplementedError();
  }

  @override
  Pointer<llama_context> llama_new_context_with_model(
    Pointer<llama_model> model,
    llama_context_params params,
  ) {
    throw UnimplementedError();
  }

  @override
  llama_model_params llama_model_default_params() {
    throw UnimplementedError();
  }

  @override
  Pointer<llama_model> llama_load_model_from_file(
    Pointer<Char> path,
    llama_model_params params,
  ) {
    throw UnimplementedError();
  }

  @override
  Pointer<llama_vocab> llama_model_get_vocab(Pointer<llama_model> model) {
    return Pointer.fromAddress(3);
  }

  @override
  void llama_log_set(
    Pointer<NativeFunction<ggml_log_callbackFunction>> cb,
    Pointer<Void> userData,
  ) {}

  @override
  void llama_numa_init(ggml_numa_strategy numa) {}

  @override
  int llama_decode(Pointer<llama_context> ctx, llama_batch batch) {
    throw UnimplementedError();
  }

  @override
  int llama_memory_seq_pos_max(llama_memory_t mem, int seqId) {
    throw UnimplementedError();
  }

  @override
  int llama_memory_seq_pos_min(llama_memory_t mem, int seqId) {
    throw UnimplementedError();
  }

  @override
  bool llama_memory_seq_rm(
    llama_memory_t mem,
    int seqId,
    int p0,
    int p1,
  ) {
    throw UnimplementedError();
  }

  @override
  llama_sampler_chain_params llama_sampler_chain_default_params() {
    throw UnimplementedError();
  }

  @override
  void llama_sampler_chain_add(
    Pointer<llama_sampler> chain,
    Pointer<llama_sampler> sampler,
  ) {}

  @override
  Pointer<llama_sampler> llama_sampler_chain_init(
    llama_sampler_chain_params params,
  ) {
    throw UnimplementedError();
  }

  @override
  void llama_sampler_free(Pointer<llama_sampler> sampler) {}

  @override
  Pointer<llama_sampler> llama_sampler_init_dist(int seed) {
    throw UnimplementedError();
  }

  @override
  Pointer<llama_sampler> llama_sampler_init_greedy() {
    throw UnimplementedError();
  }

  @override
  Pointer<llama_sampler> llama_sampler_init_min_p(double p, int minKeep) {
    throw UnimplementedError();
  }

  @override
  Pointer<llama_sampler> llama_sampler_init_penalties(
    int penaltyLastN,
    double penaltyRepeat,
    double penaltyFreq,
    double penaltyPresent,
  ) {
    throw UnimplementedError();
  }

  @override
  Pointer<llama_sampler> llama_sampler_init_temp(double temp) {
    throw UnimplementedError();
  }

  @override
  Pointer<llama_sampler> llama_sampler_init_top_k(int k) {
    throw UnimplementedError();
  }

  @override
  Pointer<llama_sampler> llama_sampler_init_top_p(double p, int minKeep) {
    throw UnimplementedError();
  }

  @override
  Pointer<llama_sampler> llama_sampler_init_typical(double p, int minKeep) {
    throw UnimplementedError();
  }

  @override
  int llama_sampler_sample(
    Pointer<llama_sampler> sampler,
    Pointer<llama_context> ctx,
    int idx,
  ) {
    throw UnimplementedError();
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
    throw UnimplementedError();
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
    throw UnimplementedError();
  }

  @override
  bool llama_vocab_is_control(Pointer<llama_vocab> vocab, int token) {
    throw UnimplementedError();
  }

  @override
  bool llama_vocab_is_eog(Pointer<llama_vocab> vocab, int token) {
    throw UnimplementedError();
  }

  @override
  Pointer<Char> llama_model_chat_template(
    Pointer<llama_model> model,
    Pointer<Char> name,
  ) {
    throw UnimplementedError();
  }

  @override
  int llama_model_meta_val_str(
    Pointer<llama_model> model,
    Pointer<Char> key,
    Pointer<Char> buf,
    int bufSize,
  ) {
    throw UnimplementedError();
  }
}
