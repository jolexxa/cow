import 'dart:ffi';
import 'dart:typed_data';

import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:test/test.dart';

import '../../../fixtures/fake_bindings.dart';

void main() {
  group('LlamaPrefillBatcher', () {
    late FakeLlamaBindings bindings;
    late _FakeClient client;
    late LlamaHandles handles;
    late LlamaPrefillBatcher batcher;

    setUp(() {
      bindings = FakeLlamaBindings();
      handles = LlamaHandles(
        bindings: bindings,
        model: Pointer.fromAddress(1),
        context: Pointer.fromAddress(2),
        vocab: Pointer.fromAddress(3),
      );
      client = _FakeClient(bindings);
      batcher = LlamaPrefillBatcher(
        client: client,
        handles: handles,
        nBatch: 512,
      );
    });

    test(
      'single sequence dispatched with correct positions and logits',
      () async {
        bindings.posMax = 4;

        final future = batcher.submitPrefill(
          sequenceId: 0,
          tokens: [10, 20, 30],
        );
        batcher.dispatchNow();

        final result = await future;
        // Final token is dispatched separately — batchIndex is 0 in that batch.
        expect(result.batchIndex, 0);
        // Two decodeBatch calls: prefill (2 tokens) + final (1 token).
        expect(client.decodeBatchCalls, 2);
        expect(client.batchEntries, hasLength(3));

        // Positions: posMax(4) + 1, +2, +3
        expect(client.batchEntries[0], (
          token: 10,
          pos: 5,
          seqId: 0,
          logits: false,
        ));
        expect(client.batchEntries[1], (
          token: 20,
          pos: 6,
          seqId: 0,
          logits: false,
        ));
        expect(client.batchEntries[2], (
          token: 30,
          pos: 7,
          seqId: 0,
          logits: true,
        ));
      },
    );

    test('two sequences coalesced into batched dispatch', () async {
      bindings.posMax = 0;

      final future0 = batcher.submitPrefill(
        sequenceId: 0,
        tokens: [10, 20, 30],
      );
      final future1 = batcher.submitPrefill(
        sequenceId: 1,
        tokens: [40, 50],
      );
      batcher.dispatchNow();

      final r0 = await future0;
      final r1 = await future1;

      // Final tokens dispatched separately — indices 0, 1 in the final batch.
      expect(r0.batchIndex, 0);
      expect(r1.batchIndex, 1);
      // Two calls: prefill (3 non-final tokens) + final (2 tokens).
      expect(client.decodeBatchCalls, 2);
      expect(client.batchEntries, hasLength(5));

      // Verify logits: only last token per sequence.
      expect(client.batchEntries[0].logits, isFalse); // seq 0 token 10
      expect(client.batchEntries[1].logits, isFalse); // seq 0 token 20
      expect(client.batchEntries[2].logits, isFalse); // seq 1 token 40
      expect(client.batchEntries[3].logits, isTrue); // seq 0 final (30)
      expect(client.batchEntries[4].logits, isTrue); // seq 1 final (50)

      // Verify sequence IDs.
      expect(client.batchEntries[0].seqId, 0);
      expect(client.batchEntries[1].seqId, 0);
      expect(client.batchEntries[2].seqId, 1);
      expect(client.batchEntries[3].seqId, 0);
      expect(client.batchEntries[4].seqId, 1);
    });

    test('empty tokens complete immediately with batchIndex -1', () async {
      final result = await batcher.submitPrefill(
        sequenceId: 0,
        tokens: [],
      );
      expect(result.batchIndex, -1);
      expect(client.decodeBatchCalls, 0);
    });

    test('error propagated to all completers', () async {
      client.shouldThrow = true;

      final future0 = batcher.submitPrefill(
        sequenceId: 0,
        tokens: [10],
      );
      final future1 = batcher.submitPrefill(
        sequenceId: 1,
        tokens: [20],
      );
      batcher.dispatchNow();

      await expectLater(future0, throwsStateError);
      await expectLater(future1, throwsStateError);
    });

    test('Timer.run dispatches submissions', () async {
      bindings.posMax = 0;

      final future = batcher.submitPrefill(
        sequenceId: 0,
        tokens: [7],
      );

      // Don't call dispatchNow — let Timer.run handle it.
      final result = await future;
      expect(result.batchIndex, 0);
      expect(client.batchEntries, hasLength(1));
      expect(client.batchEntries.first.token, 7);
    });

    test('dispatch resets scheduling flag for subsequent batches', () async {
      bindings.posMax = 0;

      // First batch.
      final f1 = batcher.submitPrefill(sequenceId: 0, tokens: [1]);
      batcher.dispatchNow();
      await f1;

      // Second batch.
      final f2 = batcher.submitPrefill(sequenceId: 0, tokens: [2]);
      batcher.dispatchNow();
      await f2;

      expect(client.decodeBatchCalls, 2);
    });

    test('empty pending list after dispatch is a no-op', () {
      batcher.dispatchNow();
      expect(client.decodeBatchCalls, 0);
    });

    test('chunks when total tokens exceed nBatch', () async {
      bindings.posMax = 0;

      // nBatch = 512, but we'll create a batcher with nBatch = 4 for testing.
      final smallBatcher = LlamaPrefillBatcher(
        client: client,
        handles: handles,
        nBatch: 4,
      );

      // Seq 0: 3 tokens, Seq 1: 3 tokens = 6 total > nBatch of 4.
      final future0 = smallBatcher.submitPrefill(
        sequenceId: 0,
        tokens: [10, 20, 30],
      );
      final future1 = smallBatcher.submitPrefill(
        sequenceId: 1,
        tokens: [40, 50, 60],
      );
      smallBatcher.dispatchNow();

      final r0 = await future0;
      final r1 = await future1;

      // Should have been dispatched in chunks (6 tokens, nBatch 4 → 2 calls).
      expect(client.decodeBatchCalls, 2);

      // Both should still get valid batch indices.
      expect(r0.batchIndex, isNonNegative);
      expect(r1.batchIndex, isNonNegative);
    });

    test('single large sequence chunked correctly', () async {
      bindings.posMax = 0;

      final smallBatcher = LlamaPrefillBatcher(
        client: client,
        handles: handles,
        nBatch: 2,
      );

      // 5 tokens, nBatch = 2 → prefill [1,2,3,4] in chunks of 2 (2 calls)
      // + final [5] in its own batch = 3 decodeBatch calls total.
      final future = smallBatcher.submitPrefill(
        sequenceId: 0,
        tokens: [1, 2, 3, 4, 5],
      );
      smallBatcher.dispatchNow();

      final result = await future;

      expect(client.decodeBatchCalls, 3);
      // batchIndex is 0 — the sole entry in the final batch.
      expect(result.batchIndex, 0);

      // Verify only the last token has logits: true.
      final logitsFlags = client.batchEntries.map((e) => e.logits).toList();
      expect(logitsFlags, [false, false, false, false, true]);
    });
  });
}

final class _FakeClient implements LlamaClientApi {
  _FakeClient(this.bindings);

  final FakeLlamaBindings bindings;
  int decodeBatchCalls = 0;
  bool shouldThrow = false;
  final List<({int token, int pos, int seqId, bool logits})> batchEntries = [];

  @override
  void decodeBatch(
    LlamaHandles handles,
    Pointer<llama_context> context,
    List<({int token, int pos, int seqId, bool logits})> entries,
  ) {
    decodeBatchCalls++;
    batchEntries.addAll(entries);
    if (shouldThrow) {
      throw StateError('decode failed');
    }
  }

  @override
  LlamaHandles loadModel({
    required String modelPath,
    required LlamaModelOptions modelOptions,
    ModelLoadProgressCallback? onProgress,
  }) => throw UnimplementedError();

  @override
  List<int> tokenize(
    LlamaHandles handles,
    String text, {
    bool addSpecial = true,
    bool parseSpecial = true,
  }) => throw UnimplementedError();

  @override
  Pointer<llama_context> createContext(
    LlamaHandles handles,
    LlamaContextOptions options, {
    int maxSequences = 1,
  }) => throw UnimplementedError();

  @override
  void decode(
    LlamaHandles handles,
    Pointer<llama_context> context,
    List<int> tokens, {
    int sequenceId = 0,
  }) => throw UnimplementedError();

  @override
  void resetContext(
    LlamaHandles handles,
    LlamaContextOptions options, {
    required int maxSequences,
  }) => throw UnimplementedError();

  @override
  int sampleNext(LlamaHandles handles, LlamaSamplerChain sampler) =>
      throw UnimplementedError();

  @override
  int sampleAt(
    LlamaHandles handles,
    LlamaSamplerChain sampler,
    int batchIndex,
  ) => throw UnimplementedError();

  @override
  Uint8List tokenToBytes(
    LlamaHandles handles,
    int token, {
    int bufferSize = 256,
  }) => throw UnimplementedError();

  @override
  void dispose(LlamaHandles handles) {}
}
