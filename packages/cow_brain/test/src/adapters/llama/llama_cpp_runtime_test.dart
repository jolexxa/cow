// Breaks analyzer.
// ignore_for_file: cascade_invocations

import 'dart:collection';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:test/test.dart';

import '../../../fixtures/fake_bindings.dart';

void main() {
  group('LlamaCppRuntime', () {
    test('creates default client when none is provided', () {
      final bindings = FakeLlamaBindings()
        ..tokenizeImpl =
            (
              _,
              _,
              _,
              Pointer<llama_token> tokens,
              _,
              _,
              _,
            ) {
              tokens[0] = 1;
              return 1;
            };
      LlamaClient.openBindings = ({required String libraryPath}) => bindings;
      addTearDown(() {
        LlamaClient.openBindings = LlamaBindingsLoader.open;
      });

      final runtime = LlamaCppRuntime(
        options: const LlamaRuntimeOptions(
          modelPath: 'model',
          libraryPath: '/tmp/libllama.so',
          contextOptions: LlamaContextOptions(
            contextSize: 32,
            nBatch: 4,
            nThreads: 1,
            nThreadsBatch: 1,
          ),
          maxOutputTokensDefault: 4,
        ),
      );

      final count = runtime.countTokens('hi', addBos: true);
      expect(count, 1);
      runtime.dispose();
    });

    test('throws when prompt exceeds context size', () async {
      final bindings = FakeLlamaBindings();
      final client = FakeClient(bindings)
        ..tokenizeResult = List<int>.filled(50, 1);

      final runtime = LlamaCppRuntime(
        options: const LlamaRuntimeOptions(
          modelPath: 'model',
          libraryPath: '/tmp/libllama.so',
          contextOptions: LlamaContextOptions(
            contextSize: 60,
            nBatch: 4,
            nThreads: 1,
            nThreadsBatch: 1,
          ),
          maxOutputTokensDefault: 20,
        ),
        client: client,
      );

      expect(
        () => runtime
            .generate(
              prompt: 'hi',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList(),
        throwsStateError,
      );
    });

    test('drops tokens when memory is full', () async {
      final bindings = FakeLlamaBindings()
        ..posMin = 0
        ..posMax = 4;
      final client = FakeClient(bindings)
        ..tokenizeResult = List<int>.filled(6, 1);

      final runtime = LlamaCppRuntime(
        options: const LlamaRuntimeOptions(
          modelPath: 'model',
          libraryPath: '/tmp/libllama.so',
          contextOptions: LlamaContextOptions(
            contextSize: 10,
            nBatch: 4,
            nThreads: 1,
            nThreadsBatch: 1,
          ),
          maxOutputTokensDefault: 4,
        ),
        client: client,
      );

      await runtime
          .generate(
            prompt: 'hi',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      expect(bindings.lastMemoryRmArgs, isNotNull);
    });

    test('throws when memory trimming fails', () async {
      final bindings = FakeLlamaBindings()
        ..posMin = 0
        ..posMax = 9
        ..memorySeqRmImpl = (_, _, _, _) => false;
      final client = FakeClient(bindings)
        ..tokenizeResult = List<int>.filled(5, 1);

      final runtime = LlamaCppRuntime(
        options: const LlamaRuntimeOptions(
          modelPath: 'model',
          libraryPath: '/tmp/libllama.so',
          contextOptions: LlamaContextOptions(
            contextSize: 12,
            nBatch: 4,
            nThreads: 1,
            nThreadsBatch: 1,
          ),
          maxOutputTokensDefault: 6,
        ),
        client: client,
      );

      expect(
        () => runtime
            .generate(
              prompt: 'hi',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList(),
        throwsStateError,
      );
    });

    test('resets context when requiresReset is true', () async {
      final bindings = FakeLlamaBindings();
      final client = FakeClient(bindings)
        ..tokenizeResult = [1]
        ..sampleQueue.add(999);

      final runtime = LlamaCppRuntime(
        options: const LlamaRuntimeOptions(
          modelPath: 'model',
          libraryPath: '/tmp/libllama.so',
          contextOptions: LlamaContextOptions(
            contextSize: 20,
            nBatch: 4,
            nThreads: 1,
            nThreadsBatch: 1,
          ),
          maxOutputTokensDefault: 4,
        ),
        client: client,
      );

      await runtime
          .generate(
            prompt: 'hi',
            stopSequences: const [],
            addBos: true,
            requiresReset: true,
            reusePrefixMessageCount: 0,
          )
          .toList();

      expect(client.resetCalled, isTrue);
    });

    test('honors stop sequences and control tokens', () async {
      final bindings = FakeLlamaBindings();
      bindings.vocabIsControlImpl = (_, token) => token == 2;
      bindings.vocabIsEogImpl = (_, token) => token == 4;
      final client = FakeClient(bindings)
        ..tokenizeResult = [1]
        ..tokenBytes[1] = 'H'.codeUnits
        ..tokenBytes[2] = 'X'.codeUnits
        ..tokenBytes[3] = 'END'.codeUnits
        ..sampleQueue.addAll([1, 2, 3, 4]);

      final runtime = LlamaCppRuntime(
        options: const LlamaRuntimeOptions(
          modelPath: 'model',
          libraryPath: '/tmp/libllama.so',
          contextOptions: LlamaContextOptions(
            contextSize: 50,
            nBatch: 4,
            nThreads: 1,
            nThreadsBatch: 1,
          ),
          maxOutputTokensDefault: 10,
        ),
        client: client,
      );

      final outputs = await runtime
          .generate(
            prompt: 'hi',
            stopSequences: const ['END'],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      final text = outputs.map((chunk) => chunk.text).join();
      expect(text, 'H');
    });

    test('splits decoding into batches', () async {
      final bindings = FakeLlamaBindings();
      final client = FakeClient(bindings)
        ..tokenizeResult = List<int>.filled(5, 1)
        ..sampleQueue.add(999);

      final runtime = LlamaCppRuntime(
        options: const LlamaRuntimeOptions(
          modelPath: 'model',
          libraryPath: '/tmp/libllama.so',
          contextOptions: LlamaContextOptions(
            contextSize: 50,
            nBatch: 2,
            nThreads: 1,
            nThreadsBatch: 1,
          ),
          maxOutputTokensDefault: 2,
        ),
        client: client,
      );

      await runtime
          .generate(
            prompt: 'hi',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      expect(client.decodeCalls, 5);
    });

    test(
      'countTokens respects BOS tracking and throws when disposed',
      () async {
        final bindings = FakeLlamaBindings()..vocabIsEogImpl = (_, _) => true;
        final client = FakeClient(bindings)
          ..tokenizeResult = [1]
          ..sampleQueue.add(2);

        final runtime = LlamaCppRuntime(
          options: const LlamaRuntimeOptions(
            modelPath: 'model',
            libraryPath: '/tmp/libllama.so',
            contextOptions: LlamaContextOptions(
              contextSize: 32,
              nBatch: 4,
              nThreads: 1,
              nThreadsBatch: 1,
            ),
            maxOutputTokensDefault: 4,
          ),
          client: client,
        );

        await runtime
            .generate(
              prompt: 'hi',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList();

        final count = runtime.countTokens('next', addBos: true);
        expect(count, 1);
        expect(client.addSpecialCalls, [true, false]);

        runtime.dispose();
        expect(() => runtime.countTokens('x', addBos: true), throwsStateError);
      },
    );

    test('reset clears BOS state and dispose is idempotent', () async {
      final bindings = FakeLlamaBindings()..vocabIsEogImpl = (_, _) => true;
      final client = FakeClient(bindings)
        ..tokenizeResult = [1]
        ..sampleQueue.add(2);

      final runtime = LlamaCppRuntime(
        options: const LlamaRuntimeOptions(
          modelPath: 'model',
          libraryPath: '/tmp/libllama.so',
          contextOptions: LlamaContextOptions(
            contextSize: 32,
            nBatch: 4,
            nThreads: 1,
            nThreadsBatch: 1,
          ),
          maxOutputTokensDefault: 4,
        ),
        client: client,
      );

      await runtime
          .generate(
            prompt: 'hi',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      runtime.reset();
      expect(client.resetCalled, isTrue);
      runtime.countTokens('next', addBos: true);
      expect(client.addSpecialCalls.last, isTrue);

      runtime.dispose();
      runtime.dispose();
      expect(client.disposeCalls, 1);
    });

    test('throws when context creation fails', () async {
      final bindings = FakeLlamaBindings();
      final client = FakeClient(bindings)
        ..tokenizeResult = [1]
        ..createContextResult = nullptr
        ..initialContext = nullptr;

      final runtime = LlamaCppRuntime(
        options: const LlamaRuntimeOptions(
          modelPath: 'model',
          libraryPath: '/tmp/libllama.so',
          contextOptions: LlamaContextOptions(
            contextSize: 32,
            nBatch: 4,
            nThreads: 1,
            nThreadsBatch: 1,
          ),
          maxOutputTokensDefault: 4,
        ),
        client: client,
      );

      expect(
        () => runtime
            .generate(
              prompt: 'hi',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList(),
        throwsStateError,
      );
    });

    test('drains decoded chunks in helper', () {
      final chunks = <String>['a', 'b'];
      final piece = drainDecodedChunksForTesting(chunks);
      expect(piece, 'ab');
      expect(chunks, isEmpty);
    });

    test('chunked string sink writes all and writeln', () {
      final chunks = <String>[];
      final sink = chunkedStringSinkForTesting(chunks);
      sink.writeAll([1, null, 'b'], ',');
      sink.writeln('x');
      sink.writeln();
      expect(chunks, ['1', ',', ',', 'b', 'x', '\n', '\n']);
    });

    test('yields pending after guard length avoids flushing', () async {
      final bindings = FakeLlamaBindings()..vocabIsEogImpl = (_, _) => false;
      final client = FakeClient(bindings)
        ..tokenizeResult = [1]
        ..tokenBytes[1] = 'a'.codeUnits
        ..sampleQueue.addAll(List<int>.filled(16, 1));
      final stopSequence = List.filled(100, 'x').join();

      final runtime = LlamaCppRuntime(
        options: const LlamaRuntimeOptions(
          modelPath: 'model',
          libraryPath: '/tmp/libllama.so',
          contextOptions: LlamaContextOptions(
            contextSize: 64,
            nBatch: 4,
            nThreads: 1,
            nThreadsBatch: 1,
          ),
          maxOutputTokensDefault: 16,
        ),
        client: client,
      );

      final output = await runtime
          .generate(
            prompt: 'hi',
            stopSequences: [stopSequence],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      final text = output.map((chunk) => chunk.text).join();
      expect(text, 'a' * 16);
    });

    test('final stop sequence check uses substring branch', () async {
      final bindings = FakeLlamaBindings()..vocabIsEogImpl = (_, _) => false;
      final client = FakeClient(bindings)
        ..tokenizeResult = [1]
        ..tokenBytes[1] = [0xC2]
        ..sampleQueue.add(1);

      final runtime = LlamaCppRuntime(
        options: const LlamaRuntimeOptions(
          modelPath: 'model',
          libraryPath: '/tmp/libllama.so',
          contextOptions: LlamaContextOptions(
            contextSize: 16,
            nBatch: 4,
            nThreads: 1,
            nThreadsBatch: 1,
          ),
          maxOutputTokensDefault: 1,
        ),
        client: client,
      );

      final output = await runtime
          .generate(
            prompt: 'hi',
            stopSequences: const ['\uFFFD'],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      final text = output.map((chunk) => chunk.text).join();
      expect(text, isEmpty);
    });
  });
}

final class FakeClient implements LlamaClientApi {
  FakeClient(this.bindings);

  final FakeLlamaBindings bindings;
  List<int> tokenizeResult = const [1];
  final List<bool> addSpecialCalls = <bool>[];
  final Queue<int> sampleQueue = Queue<int>();
  final Map<int, List<int>> tokenBytes = <int, List<int>>{};
  bool resetCalled = false;
  int decodeCalls = 0;
  int disposeCalls = 0;
  Pointer<llama_context> createContextResult = Pointer.fromAddress(2);
  Pointer<llama_context> initialContext = Pointer.fromAddress(2);

  @override
  LlamaHandles loadModel({
    required String modelPath,
    required LlamaModelOptions modelOptions,
  }) {
    return LlamaHandles(
      bindings: bindings,
      model: Pointer.fromAddress(1),
      context: initialContext,
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
    addSpecialCalls.add(addSpecial);
    return tokenizeResult;
  }

  @override
  void resetContext(
    LlamaHandles handles,
    LlamaContextOptions options,
  ) {
    resetCalled = true;
  }

  @override
  Pointer<llama_context> createContext(
    LlamaHandles handles,
    LlamaContextOptions options,
  ) {
    return createContextResult;
  }

  @override
  void decode(
    LlamaHandles handles,
    Pointer<llama_context> context,
    List<int> tokens,
  ) {
    decodeCalls += 1;
  }

  @override
  int sampleNext(
    LlamaHandles handles,
    LlamaSamplerChain sampler,
  ) {
    if (sampleQueue.isEmpty) {
      return 0;
    }
    return sampleQueue.removeFirst();
  }

  @override
  Uint8List tokenToBytes(
    LlamaHandles handles,
    int token, {
    int bufferSize = 256,
  }) {
    return Uint8List.fromList(tokenBytes[token] ?? <int>[token]);
  }

  @override
  void dispose(LlamaHandles handles) {
    disposeCalls += 1;
  }
}
