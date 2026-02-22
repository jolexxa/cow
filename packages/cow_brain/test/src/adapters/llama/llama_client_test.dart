import 'dart:ffi';

import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:ffi/ffi.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:test/test.dart';

import '../../../fixtures/fake_bindings.dart';

void main() {
  group('LlamaClient', () {
    late FakeLlamaBindings bindings;

    setUp(() {
      bindings = FakeLlamaBindings();
      LlamaClient.openBindings = ({required String libraryPath}) => bindings;
    });

    tearDown(() {
      LlamaClient.openBindings = LlamaBindingsLoader.open;
    });

    test('tokenize reallocates when needed and returns tokens', () {
      var call = 0;
      bindings.tokenizeImpl =
          (
            _,
            _,
            _,
            Pointer<llama_token> tokens,
            _,
            _,
            _,
          ) {
            call += 1;
            if (call == 1) return -3;
            tokens[0] = 1;
            tokens[1] = 2;
            tokens[2] = 3;
            return 3;
          };

      final client = _client();
      final handles = _handles(client);

      final tokens = client.tokenize(handles, 'hi');
      expect(tokens, [1, 2, 3]);
    });

    test('tokenize throws when tokenization fails twice', () {
      bindings.tokenizeImpl =
          (
            _,
            _,
            _,
            _,
            _,
            _,
            _,
          ) => -2;

      final client = _client();
      final handles = _handles(client);

      expect(
        () => client.tokenize(handles, 'hi'),
        throwsStateError,
      );
    });

    test('tokenToPiece returns empty string when conversion fails', () {
      bindings.tokenToPieceImpl =
          (
            _,
            _,
            _,
            _,
            _,
            _,
          ) => -1;

      final client = _client();
      final handles = _handles(client);

      expect(client.tokenToPiece(handles, 1), isEmpty);
    });

    test('tokenToPiece returns decoded text when conversion succeeds', () {
      bindings.tokenToPieceImpl =
          (
            _,
            _,
            Pointer<Char> buf,
            _,
            _,
            _,
          ) {
            final bytes = 'ok'.codeUnits;
            for (var i = 0; i < bytes.length; i += 1) {
              buf.cast<Uint8>()[i] = bytes[i];
            }
            return bytes.length;
          };

      final client = _client();
      final handles = _handles(client);

      expect(client.tokenToPiece(handles, 1), 'ok');
    });

    test('tokenToBytes returns bytes for valid tokens', () {
      bindings.tokenToPieceImpl =
          (
            _,
            _,
            Pointer<Char> buf,
            _,
            _,
            _,
          ) {
            final bytes = 'ok'.codeUnits;
            for (var i = 0; i < bytes.length; i += 1) {
              buf.cast<Uint8>()[i] = bytes[i];
            }
            return bytes.length;
          };

      final client = _client();
      final handles = _handles(client);

      final bytes = client.tokenToBytes(handles, 1);
      expect(bytes, 'ok'.codeUnits);
    });

    test('tokenToBytes returns empty when conversion fails', () {
      bindings.tokenToPieceImpl =
          (
            _,
            _,
            _,
            _,
            _,
            _,
          ) => -1;

      final client = _client();
      final handles = _handles(client);

      final bytes = client.tokenToBytes(handles, 1);
      expect(bytes, isEmpty);
    });

    test('createContext applies flash attention options', () {
      bindings.contextParams = calloc<llama_context_params>().ref;

      final client = _client();
      final handles = _handles(client);

      client.createContext(
        handles,
        const LlamaContextOptions(
          contextSize: 8,
          nBatch: 1,
          nThreads: 1,
          nThreadsBatch: 1,
          useFlashAttn: true,
        ),
      );

      expect(
        bindings.contextParams.flash_attn_typeAsInt,
        llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_ENABLED.value,
      );
    });

    test('createContext applies flash attention disabled', () {
      bindings.contextParams = calloc<llama_context_params>().ref;

      final client = _client();
      final handles = _handles(client);

      client.createContext(
        handles,
        const LlamaContextOptions(
          contextSize: 8,
          nBatch: 1,
          nThreads: 1,
          nThreadsBatch: 1,
          useFlashAttn: false,
        ),
      );

      expect(
        bindings.contextParams.flash_attn_typeAsInt,
        llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_DISABLED.value,
      );
    });

    test('loadModel applies model options and configures logging', () {
      LlamaClient(libraryPath: '/tmp/libllama.so').loadModel(
        modelPath: 'model',
        modelOptions: const LlamaModelOptions(),
      );

      final client = LlamaClient(libraryPath: '/tmp/libllama.so');
      final handles = client.loadModel(
        modelPath: 'model',
        modelOptions: LlamaModelOptions(
          nGpuLayers: 7,
          mainGpu: 1,
          useMmap: true,
          useMlock: false,
          checkTensors: true,
          numa: ggml_numa_strategy.GGML_NUMA_STRATEGY_DISTRIBUTE.value,
        ),
      );

      expect(bindings.backendInitCalls, 0);
      expect(bindings.llamaLogSetCalls, 0);
      expect(bindings.ggmlLogSetCalls, 0);
      expect(
        bindings.lastNumaInit?.value,
        ggml_numa_strategy.GGML_NUMA_STRATEGY_DISTRIBUTE.value,
      );
      expect(bindings.modelParams.n_gpu_layers, 7);
      expect(bindings.modelParams.main_gpu, 1);
      expect(bindings.modelParams.use_mmap, isTrue);
      expect(bindings.modelParams.use_mlock, isFalse);
      expect(bindings.modelParams.check_tensors, isTrue);
      expect(handles.model, isNot(equals(nullptr)));
    });

    test('loadModel throws when model fails to load', () {
      bindings.modelPtr = nullptr;

      final client = LlamaClient(libraryPath: '/tmp/libllama.so');
      expect(
        () => client.loadModel(
          modelPath: 'missing',
          modelOptions: const LlamaModelOptions(),
        ),
        throwsStateError,
      );
    });

    test('decode throws when llama_decode returns non-zero', () {
      bindings.decodeImpl = (_, _) => 1;

      final client = _client();
      final handles = _handles(client);

      expect(
        () => client.decode(handles, Pointer.fromAddress(1), [1]),
        throwsStateError,
      );
    });

    test('decode is a no-op for empty token lists', () {
      final client = _client();
      final handles = _handles(client);

      client.decode(handles, Pointer.fromAddress(1), const []);
      expect(bindings.decodeCalls, 0);
    });

    test('resetContext throws when context creation fails', () {
      bindings.newContextImpl = (_, _) => nullptr;

      final client = _client();
      final handles = _handles(client);

      expect(
        () => client.resetContext(
          handles,
          const LlamaContextOptions(
            contextSize: 8,
            nBatch: 1,
            nThreads: 1,
            nThreadsBatch: 1,
          ),
        ),
        throwsStateError,
      );
    });

    test('freeContext clears context and dispose frees resources', () {
      final client = LlamaClient(libraryPath: '/tmp/libllama.so');
      final handles = client.loadModel(
        modelPath: 'model',
        modelOptions: const LlamaModelOptions(),
      )..context = Pointer.fromAddress(99);

      client.freeContext(handles);
      expect(handles.context, equals(nullptr));
      expect(bindings.freeCalls, 1);

      handles.context = Pointer.fromAddress(98);
      client.dispose(handles);
      expect(bindings.freeCalls, 2);
      expect(bindings.freeModelCalls, 1);
      expect(bindings.backendFreeCalls, 0);
    });

    test('sampleNext delegates to the sampler', () {
      bindings.samplerSampleResult = 42;

      final client = _client();
      final handles = _handles(client);

      final sampler = LlamaSamplerChain.build(
        bindings,
        const SamplingOptions(),
      );

      final value = client.sampleNext(handles, sampler);
      expect(value, 42);
      expect(bindings.samplerSampleCalls, 1);
      sampler.dispose();
    });

    test('sampler chain adds expected samplers for greedy and temp modes', () {
      final greedy = LlamaSamplerChain.build(
        bindings,
        const SamplingOptions(
          temperature: 0,
          topK: 10,
          topP: 0.9,
          minP: 0.2,
          typicalP: 0.8,
          penaltyRepeat: 1.2,
          penaltyLastN: 32,
        ),
      );
      expect(bindings.samplerChainAddCalls, 6);
      greedy.dispose();
      expect(bindings.samplerFreeCalls, 1);

      bindings
        ..samplerChainAddCalls = 0
        ..samplerFreeCalls = 0;

      final temp = LlamaSamplerChain.build(
        bindings,
        const SamplingOptions(
          temperature: 0.7,
          topK: 40,
          topP: 0.95,
          minP: 0.05,
          typicalP: 1,
          penaltyRepeat: 1.1,
          penaltyLastN: 64,
          seed: 7,
        ),
      );
      expect(bindings.samplerChainAddCalls, 6);
      temp.dispose();
      expect(bindings.samplerFreeCalls, 1);
    });

    test('loadModel with progress callback sets up native callback', () {
      final progressValues = <double>[];
      final client = LlamaClient(libraryPath: '/tmp/libllama.so');

      final handles = client.loadModel(
        modelPath: 'model',
        modelOptions: const LlamaModelOptions(),
        onProgress: (progress) {
          progressValues.add(progress);
          return true;
        },
      );

      // The callback is set up even if not invoked during test.
      expect(handles.model, isNot(equals(nullptr)));
    });

    test('modelPointerAddress returns model address', () {
      final client = _client();
      final handles = _handles(client);

      expect(handles.modelPointerAddress, handles.model.address);
    });
  });
}

LlamaClient _client() => LlamaClient(libraryPath: '/tmp/libllama.so');

LlamaHandles _handles(LlamaClient client) {
  return client.loadModel(
    modelPath: 'model',
    modelOptions: const LlamaModelOptions(),
  );
}
