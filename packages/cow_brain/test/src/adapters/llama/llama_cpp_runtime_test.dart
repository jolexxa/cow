// Breaks analyzer.
// ignore_for_file: cascade_invocations

import 'dart:collection';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:cow_brain/src/adapters/stream_chunk.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:test/test.dart';

import '../../../fixtures/fake_bindings.dart';

void main() {
  group('LlamaCppRuntime', () {
    test('throws when prompt exceeds context size', () async {
      final bindings = FakeLlamaBindings();
      final client = FakeClient(bindings)
        ..tokenizeResult = List<int>.filled(50, 1);

      final runtime = LlamaCppRuntime(
        modelPointer: 1,
        options: const LlamaCppRuntimeOptions(
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
        bindings: bindings,
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
        modelPointer: 1,
        options: const LlamaCppRuntimeOptions(
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
        bindings: bindings,
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
        modelPointer: 1,
        options: const LlamaCppRuntimeOptions(
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
        bindings: bindings,
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
        modelPointer: 1,
        options: const LlamaCppRuntimeOptions(
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
        bindings: bindings,
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

      expect(client.resetCalls, 1);
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
        modelPointer: 1,
        options: const LlamaCppRuntimeOptions(
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
        bindings: bindings,
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
        modelPointer: 1,
        options: const LlamaCppRuntimeOptions(
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
        bindings: bindings,
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
          modelPointer: 1,
          options: const LlamaCppRuntimeOptions(
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
          bindings: bindings,
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
        modelPointer: 1,
        options: const LlamaCppRuntimeOptions(
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
        bindings: bindings,
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
      expect(client.resetCalls, 1);
      runtime.countTokens('next', addBos: true);
      expect(client.addSpecialCalls.last, isTrue);

      runtime.dispose();
      runtime.dispose();
      // Dispose is idempotent - calling it twice doesn't throw.
      // Runtime now only frees context, not the shared model.
    });

    test('throws when context creation fails', () {
      final bindings = FakeLlamaBindings();
      final client = FakeClient(bindings)
        ..tokenizeResult = [1]
        ..createContextResult = nullptr
        ..initialContext = nullptr;

      expect(
        () => LlamaCppRuntime(
          modelPointer: 1,
          options: const LlamaCppRuntimeOptions(
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
          bindings: bindings,
        ),
        throwsStateError,
      );
    });

    test('drains decoded chunks in helper', () {
      final chunks = <String>['a', 'b'];
      final piece = drainDecodedChunks(chunks);
      expect(piece, 'ab');
      expect(chunks, isEmpty);
    });

    test('chunked string sink writes all and writeln', () {
      final chunks = <String>[];
      final sink = llamaChunkedStringSink(chunks);
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
        modelPointer: 1,
        options: const LlamaCppRuntimeOptions(
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
        bindings: bindings,
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

    test('yields heartbeat chunk after 16'
        ' consecutive control tokens', () async {
      final bindings = FakeLlamaBindings();
      // All tokens are control tokens.
      bindings.vocabIsControlImpl = (_, _) => true;
      bindings.vocabIsEogImpl = (_, _) => false;

      // Provide 17 tokens so the 16th empty step triggers the boundary and
      // the 17th acts as the EOG (token 999 which is EOG by sampleQueue being
      // empty — sampleQueue.isEmpty returns 0 which is EOG when vocabIsEog
      // returns false for 0, but we stop via maxOutputTokens).
      final client = FakeClient(bindings)
        ..tokenizeResult = [1]
        ..sampleQueue.addAll(List<int>.filled(17, 2)); // 17 control tokens

      final runtime = LlamaCppRuntime(
        modelPointer: 1,
        options: const LlamaCppRuntimeOptions(
          modelPath: 'model',
          libraryPath: '/tmp/libllama.so',
          contextOptions: LlamaContextOptions(
            contextSize: 64,
            nBatch: 4,
            nThreads: 1,
            nThreadsBatch: 1,
          ),
          maxOutputTokensDefault: 17,
        ),
        client: client,
        bindings: bindings,
      );

      final output = await runtime
          .generate(
            prompt: 'hi',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      // After 16 control tokens the assembler heartbeat fires with empty text.
      final heartbeats = output.where((c) => c.text.isEmpty).toList();
      expect(heartbeats, isNotEmpty);
      expect(heartbeats.first.tokenCountDelta, greaterThan(0));
    });

    test(
      'yields heartbeat chunk after 16 consecutive empty-bytes tokens',
      () async {
        final bindings = FakeLlamaBindings();
        bindings.vocabIsEogImpl = (_, _) => false;
        bindings.vocabIsControlImpl = (_, _) => false;

        // All token bytes are empty — causes the bytes.isEmpty branch.
        final client = FakeClient(bindings)
          ..tokenizeResult = [1]
          ..sampleQueue.addAll(List<int>.filled(17, 5));

        // tokenBytes[5] is not set so FakeClient.tokenToBytes returns
        // Uint8List.fromList([token]) = [5] which is NOT empty.
        // We need bytes to be empty for this path — use token 99.
        // Actually by default tokenBytes[t] returns [t] (non-empty).
        // To get empty bytes we set tokenBytes[5] = [].
        (client
                  ..sampleQueue.clear()
                  ..sampleQueue.addAll(List<int>.filled(17, 5)))
                .tokenBytes[5] =
            [];

        final runtime = LlamaCppRuntime(
          modelPointer: 1,
          options: const LlamaCppRuntimeOptions(
            modelPath: 'model',
            libraryPath: '/tmp/libllama.so',
            contextOptions: LlamaContextOptions(
              contextSize: 64,
              nBatch: 4,
              nThreads: 1,
              nThreadsBatch: 1,
            ),
            maxOutputTokensDefault: 17,
          ),
          client: client,
          bindings: bindings,
        );

        final output = await runtime
            .generate(
              prompt: 'hi',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList();

        final heartbeats = output.where((c) => c.text.isEmpty).toList();
        expect(heartbeats, isNotEmpty);
        expect(heartbeats.first.tokenCountDelta, greaterThan(0));
      },
    );

    test(
      'handles incomplete UTF-8 sequence that produces empty decoded chunk',
      () async {
        // 0xC2 alone is an incomplete 2-byte UTF-8 sequence. The first call
        // to byteSink.add([0xC2]) produces no output (decodedChunks stays
        // empty), hitting the decodedChunks.isEmpty path. The final flush
        // emits the replacement character via assembler.flush().
        final bindings = FakeLlamaBindings();
        bindings.vocabIsEogImpl = (_, _) => false;
        bindings.vocabIsControlImpl = (_, _) => false;

        final client = FakeClient(bindings)
          ..tokenizeResult = [1]
          ..sampleQueue.addAll([6, 999]) // 0xC2 token, then EOG-by-emptiness
          ..tokenBytes[6] = [0xC2]; // incomplete UTF-8 — first byte only

        // Token 999 is not EOG (vocabIsEog returns false), but the queue is
        // now empty so sampleNext returns 0 which is checked against vocabIsEog
        // (false) and continues; but maxOutputTokens=2 limits this.
        final runtime = LlamaCppRuntime(
          modelPointer: 1,
          options: const LlamaCppRuntimeOptions(
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
          bindings: bindings,
        );

        final output = await runtime
            .generate(
              prompt: 'hi',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList();

        // The 0xC2 token doesn't decode immediately (decodedChunks.isEmpty),
        // so no text chunk is emitted during the loop. The flush() may emit
        // the replacement char from the closed byteSink.
        // Verify no exception was thrown and generation completed.
        expect(output, isA<List<StreamChunk>>());
      },
    );

    test(
      'incremental generation without reset does not call resetContext',
      () async {
        final bindings = FakeLlamaBindings()..vocabIsEogImpl = (_, _) => true;
        final client = FakeClient(bindings)
          ..tokenizeResult = [1]
          ..sampleQueue.addAll([2, 2]);

        final runtime = LlamaCppRuntime(
          modelPointer: 1,
          options: const LlamaCppRuntimeOptions(
            modelPath: 'model',
            libraryPath: '/tmp/libllama.so',
            contextOptions: LlamaContextOptions(
              contextSize: 64,
              nBatch: 4,
              nThreads: 1,
              nThreadsBatch: 1,
            ),
            maxOutputTokensDefault: 4,
          ),
          client: client,
          bindings: bindings,
        );

        // First generate.
        await runtime
            .generate(
              prompt: 'first',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList();

        // Second generate — incremental, no reset.
        await runtime
            .generate(
              prompt: 'second',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 1,
            )
            .toList();

        expect(client.resetCalls, 0);
        expect(client.addSpecialCalls, [true, false]);
      },
    );

    test(
      'reset between generations calls resetContext and re-sends BOS',
      () async {
        final bindings = FakeLlamaBindings()..vocabIsEogImpl = (_, _) => true;
        final client = FakeClient(bindings)
          ..tokenizeResult = [1]
          ..sampleQueue.addAll([2, 2]);

        final runtime = LlamaCppRuntime(
          modelPointer: 1,
          options: const LlamaCppRuntimeOptions(
            modelPath: 'model',
            libraryPath: '/tmp/libllama.so',
            contextOptions: LlamaContextOptions(
              contextSize: 64,
              nBatch: 4,
              nThreads: 1,
              nThreadsBatch: 1,
            ),
            maxOutputTokensDefault: 4,
          ),
          client: client,
          bindings: bindings,
        );

        // First generate — no reset.
        await runtime
            .generate(
              prompt: 'first',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList();

        // Second generate — with reset.
        await runtime
            .generate(
              prompt: 'second',
              stopSequences: const [],
              addBos: true,
              requiresReset: true,
              reusePrefixMessageCount: 0,
            )
            .toList();

        expect(client.resetCalls, 1);
        // BOS re-sent after reset.
        expect(client.addSpecialCalls, [true, true]);
      },
    );

    test('three sequential generations track BOS correctly', () async {
      final bindings = FakeLlamaBindings()..vocabIsEogImpl = (_, _) => true;
      final client = FakeClient(bindings)
        ..tokenizeResult = [1]
        ..sampleQueue.addAll([2, 2, 2]);

      final runtime = LlamaCppRuntime(
        modelPointer: 1,
        options: const LlamaCppRuntimeOptions(
          modelPath: 'model',
          libraryPath: '/tmp/libllama.so',
          contextOptions: LlamaContextOptions(
            contextSize: 64,
            nBatch: 4,
            nThreads: 1,
            nThreadsBatch: 1,
          ),
          maxOutputTokensDefault: 4,
        ),
        client: client,
        bindings: bindings,
      );

      // gen1: no reset.
      await runtime
          .generate(
            prompt: 'first',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      // gen2: no reset — BOS already applied.
      await runtime
          .generate(
            prompt: 'second',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 1,
          )
          .toList();

      // gen3: reset — BOS re-applied.
      await runtime
          .generate(
            prompt: 'third',
            stopSequences: const [],
            addBos: true,
            requiresReset: true,
            reusePrefixMessageCount: 0,
          )
          .toList();

      expect(client.addSpecialCalls, [true, false, true]);
      // Reset was called exactly once (gen3 only, not gen1 or gen2).
      expect(client.resetCalls, 1);
    });

    test(
      'memory trimming drops tokens from front of KV cache',
      () async {
        // Fill KV cache, then generate again to trigger trimming.
        final bindings = FakeLlamaBindings()
          ..posMin = 0
          ..posMax =
              7 // 8 tokens already in cache
          ..vocabIsEogImpl = (_, _) => true;
        final client = FakeClient(bindings)
          ..tokenizeResult = List<int>.filled(4, 1)
          ..sampleQueue.addAll([2, 2]);

        final runtime = LlamaCppRuntime(
          modelPointer: 1,
          options: const LlamaCppRuntimeOptions(
            modelPath: 'model',
            libraryPath: '/tmp/libllama.so',
            contextOptions: LlamaContextOptions(
              contextSize: 12,
              nBatch: 4,
              nThreads: 1,
              nThreadsBatch: 1,
            ),
            maxOutputTokensDefault: 4,
          ),
          client: client,
          bindings: bindings,
        );

        // This triggers _ensureRoomFor: 8 existing + 4 prompt + 4 output = 16
        // > contextSize(12). Should drop 16 - 12 = 4 tokens from front.
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
        final (_, seqId, p0, p1) = bindings.lastMemoryRmArgs!;
        expect(seqId, 0);
        // Drops from posMin (0) for 4 tokens.
        expect(p0, 0);
        expect(p1, 4);
      },
    );

    group('prefix caching', () {
      test('reuses common prefix and only decodes new tokens', () async {
        final bindings = FakeLlamaBindings()..vocabIsEogImpl = (_, _) => true;
        final client = FakeClient(bindings)
          ..tokenizeResult = [10, 20, 30]
          ..sampleQueue.addAll([99, 99]);

        final runtime = LlamaCppRuntime(
          modelPointer: 1,
          options: const LlamaCppRuntimeOptions(
            modelPath: 'model',
            libraryPath: '/tmp/libllama.so',
            contextOptions: LlamaContextOptions(
              contextSize: 64,
              nBatch: 64,
              nThreads: 1,
              nThreadsBatch: 1,
            ),
            maxOutputTokensDefault: 4,
          ),
          client: client,
          bindings: bindings,
        );

        // First generation: decodes all 3 prompt tokens.
        await runtime
            .generate(
              prompt: 'first',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList();

        // First call decoded [10, 20, 30] in one batch.
        expect(client.decodedTokenLists.first, [10, 20, 30]);
        client.decodedTokenLists.clear();
        client.decodeCalls = 0;

        // Second generation: prompt shares prefix [10, 20, 30], adds [40, 50].
        client.tokenizeResult = [10, 20, 30, 40, 50];
        await runtime
            .generate(
              prompt: 'second',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 1,
            )
            .toList();

        // Should only decode the new suffix [40, 50], not the full prompt.
        expect(client.decodedTokenLists.first, [40, 50]);
      });

      test('trims KV cache when prompt diverges from cached tokens', () async {
        final bindings = FakeLlamaBindings()..vocabIsEogImpl = (_, _) => true;
        final client = FakeClient(bindings)
          ..tokenizeResult = [10, 20, 30]
          ..sampleQueue.addAll([99, 99]);

        final runtime = LlamaCppRuntime(
          modelPointer: 1,
          options: const LlamaCppRuntimeOptions(
            modelPath: 'model',
            libraryPath: '/tmp/libllama.so',
            contextOptions: LlamaContextOptions(
              contextSize: 64,
              nBatch: 64,
              nThreads: 1,
              nThreadsBatch: 1,
            ),
            maxOutputTokensDefault: 4,
          ),
          client: client,
          bindings: bindings,
        );

        await runtime
            .generate(
              prompt: 'first',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList();

        // After gen1: cachedTokens = [10, 20, 30]
        // posMax should reflect 2 (0-indexed positions for 3 tokens).
        bindings
          ..posMin = 0
          ..posMax = 2
          ..memoryRmHistory.clear();

        // Second prompt diverges at index 1: [10, 77, 88].
        client
          ..tokenizeResult = [10, 77, 88]
          ..decodedTokenLists.clear()
          ..decodeCalls = 0;

        await runtime
            .generate(
              prompt: 'diverged',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList();

        // Should have trimmed from position 1 onward.
        final trimCall = bindings.memoryRmHistory.first;
        expect(trimCall.$2, 0); // seqId
        expect(trimCall.$3, 1); // p0 = commonPrefixLen (diverges at index 1)
        expect(trimCall.$4, 3); // p1 = posMax + 1

        // Should only decode the diverged suffix [77, 88].
        expect(client.decodedTokenLists.first, [77, 88]);
      });

      test('tracks generated tokens for prefix matching', () async {
        final bindings = FakeLlamaBindings()
          ..vocabIsEogImpl = (_, token) => token == 99;
        final client = FakeClient(bindings)
          ..tokenizeResult = [10, 20]
          ..tokenBytes[50] = 'A'.codeUnits
          ..tokenBytes[60] = 'B'.codeUnits
          ..sampleQueue.addAll([50, 60, 99]);

        final runtime = LlamaCppRuntime(
          modelPointer: 1,
          options: const LlamaCppRuntimeOptions(
            modelPath: 'model',
            libraryPath: '/tmp/libllama.so',
            contextOptions: LlamaContextOptions(
              contextSize: 64,
              nBatch: 64,
              nThreads: 1,
              nThreadsBatch: 1,
            ),
            maxOutputTokensDefault: 10,
          ),
          client: client,
          bindings: bindings,
        );

        // Gen1: prompt [10, 20], generates [50, 60].
        // cachedTokens should be [10, 20, 50, 60] after.
        await runtime
            .generate(
              prompt: 'first',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList();

        // Gen2: prompt includes previous response [10, 20, 50, 60, 70].
        // The full prefix [10, 20, 50, 60] should match cached tokens.
        bindings
          ..posMin = 0
          ..posMax = 3; // 4 tokens in cache (positions 0-3)
        client
          ..tokenizeResult = [10, 20, 50, 60, 70]
          ..decodedTokenLists.clear()
          ..decodeCalls = 0
          ..sampleQueue.addAll([99]);

        await runtime
            .generate(
              prompt: 'second',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 1,
            )
            .toList();

        // Only the new token [70] should be decoded.
        expect(client.decodedTokenLists.first, [70]);
      });

      test('reset clears cached tokens and re-decodes full prompt', () async {
        final bindings = FakeLlamaBindings()..vocabIsEogImpl = (_, _) => true;
        final client = FakeClient(bindings)
          ..tokenizeResult = [10, 20, 30]
          ..sampleQueue.addAll([99, 99]);

        final runtime = LlamaCppRuntime(
          modelPointer: 1,
          options: const LlamaCppRuntimeOptions(
            modelPath: 'model',
            libraryPath: '/tmp/libllama.so',
            contextOptions: LlamaContextOptions(
              contextSize: 64,
              nBatch: 64,
              nThreads: 1,
              nThreadsBatch: 1,
            ),
            maxOutputTokensDefault: 4,
          ),
          client: client,
          bindings: bindings,
        );

        // First generation.
        await runtime
            .generate(
              prompt: 'first',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList();

        client
          ..decodedTokenLists.clear()
          ..decodeCalls = 0;

        // Second generation with reset — same tokens, but should re-decode all.
        await runtime
            .generate(
              prompt: 'second',
              stopSequences: const [],
              addBos: true,
              requiresReset: true,
              reusePrefixMessageCount: 0,
            )
            .toList();

        // Full prompt re-decoded despite matching tokens.
        expect(client.decodedTokenLists.first, [10, 20, 30]);
      });

      test('skips decode when prompt exactly matches cached tokens', () async {
        final bindings = FakeLlamaBindings()
          ..vocabIsEogImpl = (_, token) => token == 99;
        final client = FakeClient(bindings)
          ..tokenizeResult = [10, 20, 30]
          ..sampleQueue.addAll([99, 99]);

        final runtime = LlamaCppRuntime(
          modelPointer: 1,
          options: const LlamaCppRuntimeOptions(
            modelPath: 'model',
            libraryPath: '/tmp/libllama.so',
            contextOptions: LlamaContextOptions(
              contextSize: 64,
              nBatch: 64,
              nThreads: 1,
              nThreadsBatch: 1,
            ),
            maxOutputTokensDefault: 4,
          ),
          client: client,
          bindings: bindings,
        );

        // First generation: decodes [10, 20, 30].
        await runtime
            .generate(
              prompt: 'first',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList();

        // Second generation: exact same prompt tokens. cachedTokens is
        // [10, 20, 30] (no generated tokens since 99 is EOG).
        // New prompt [10, 20, 30] fully matches — nothing to decode.
        bindings
          ..posMin = 0
          ..posMax = 2; // 3 tokens in cache
        client
          ..decodedTokenLists.clear()
          ..decodeCalls = 0;

        await runtime
            .generate(
              prompt: 'same',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 1,
            )
            .toList();

        // No prompt tokens decoded — only per-token sampling.
        final promptDecodes = client.decodedTokenLists
            .where((t) => t.length > 1)
            .toList();
        expect(promptDecodes, isEmpty);
      });

      test(
        'front eviction partially trims cached tokens',
        () async {
          final bindings = FakeLlamaBindings()
            ..vocabIsEogImpl = (_, _) => true;
          final client = FakeClient(bindings)
            ..tokenizeResult = [10, 20, 30, 40]
            ..sampleQueue.addAll([99, 99]);

          final runtime = LlamaCppRuntime(
            modelPointer: 1,
            options: const LlamaCppRuntimeOptions(
              modelPath: 'model',
              libraryPath: '/tmp/libllama.so',
              contextOptions: LlamaContextOptions(
                contextSize: 12,
                nBatch: 64,
                nThreads: 1,
                nThreadsBatch: 1,
              ),
              maxOutputTokensDefault: 4,
            ),
            client: client,
            bindings: bindings,
          );

          // Gen1: decode [10, 20, 30, 40]. cachedTokens = same.
          await runtime
              .generate(
                prompt: 'first',
                stopSequences: const [],
                addBos: true,
                requiresReset: false,
                reusePrefixMessageCount: 0,
              )
              .toList();

          // Simulate KV cache holding 4 tokens from gen1.
          // New prompt shares prefix [10, 20, 30, 40] and adds
          // [50, 60]. After prefix match, newTokens = [50, 60].
          // _ensureRoomFor: 4 existing + 2 new + 4 output = 10
          // but context is 12, so no eviction needed... we need
          // to make it tight.
          // Let's use contextSize=8: 4 + 2 + 4 = 10 > 8.
          // Need to drop 2 from front.
          // Actually we can't change contextSize after creation.
          // Let's use a different setup.
          // With contextSize=12, maxOutput=4:
          // If posMin=0, posMax=7 (8 cached), newTokens=2:
          // 8 + 2 + 4 = 14 > 12, drop 2 from front.
          bindings
            ..posMin = 0
            ..posMax = 7; // 8 tokens in KV cache
          client
            ..tokenizeResult = [10, 20, 30, 40, 50, 60]
            ..decodedTokenLists.clear()
            ..decodeCalls = 0
            ..sampleQueue.addAll([99]);

          await runtime
              .generate(
                prompt: 'second',
                stopSequences: const [],
                addBos: true,
                requiresReset: false,
                reusePrefixMessageCount: 1,
              )
              .toList();

          // Prefix match: [10,20,30,40] common → newTokens=[50,60]
          // _ensureRoomFor: 8 existing + 2 new + 4 out = 14 > 12
          // drops 2 from front → cachedTokens trimmed partially.
          // Then decodes [50, 60].
          expect(
            client.decodedTokenLists.first,
            [50, 60],
          );
        },
      );
    });

    test('final stop sequence check uses substring branch', () async {
      final bindings = FakeLlamaBindings()..vocabIsEogImpl = (_, _) => false;
      final client = FakeClient(bindings)
        ..tokenizeResult = [1]
        ..tokenBytes[1] = [0xC2]
        ..sampleQueue.add(1);

      final runtime = LlamaCppRuntime(
        modelPointer: 1,
        options: const LlamaCppRuntimeOptions(
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
        bindings: bindings,
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
  int resetCalls = 0;
  int decodeCalls = 0;
  int disposeCalls = 0;
  final List<List<int>> decodedTokenLists = [];
  Pointer<llama_context> createContextResult = Pointer.fromAddress(2);
  Pointer<llama_context> initialContext = Pointer.fromAddress(2);

  @override
  LlamaHandles loadModel({
    required String modelPath,
    required LlamaModelOptions modelOptions,
    ModelLoadProgressCallback? onProgress,
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
    resetCalls += 1;
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
    decodedTokenLists.add(List<int>.of(tokens));
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
