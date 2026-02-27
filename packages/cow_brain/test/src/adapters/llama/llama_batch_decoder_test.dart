import 'dart:ffi';
import 'dart:typed_data';

import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:test/test.dart';

import '../../../fixtures/fake_bindings.dart';

void main() {
  group('LlamaBatchDecoder', () {
    late FakeLlamaBindings bindings;
    late _FakeClient client;
    late LlamaHandles handles;
    late LlamaBatchDecoder decoder;

    setUp(() {
      bindings = FakeLlamaBindings();
      handles = LlamaHandles(
        bindings: bindings,
        model: Pointer.fromAddress(1),
        context: Pointer.fromAddress(2),
        vocab: Pointer.fromAddress(3),
      );
      client = _FakeClient(bindings);
      decoder = LlamaBatchDecoder(client: client, handles: handles);
    });

    test('single token dispatched with correct seq_id and position', () async {
      bindings.posMax = 4;

      final future = decoder.submitToken(token: 42, sequenceId: 0);
      decoder.dispatchNow();

      final result = await future;
      expect(result.batchIndex, 0);
      expect(client.batchEntries, hasLength(1));
      expect(client.batchEntries.first.token, 42);
      expect(client.batchEntries.first.pos, 5); // posMax + 1
      expect(client.batchEntries.first.seqId, 0);
      expect(client.batchEntries.first.logits, isTrue);
    });

    test('two sequences batched in single dispatch', () async {
      bindings.posMax = 9;

      final future0 = decoder.submitToken(token: 10, sequenceId: 0);
      final future1 = decoder.submitToken(token: 20, sequenceId: 1);
      decoder.dispatchNow();

      final r0 = await future0;
      final r1 = await future1;
      expect(r0.batchIndex, 0);
      expect(r1.batchIndex, 1);
      expect(client.decodeBatchCalls, 1);
      expect(client.batchEntries, hasLength(2));
      expect(client.batchEntries[0].seqId, 0);
      expect(client.batchEntries[1].seqId, 1);
    });

    test('error propagated to all completers', () async {
      client.shouldThrow = true;

      final future0 = decoder.submitToken(token: 10, sequenceId: 0);
      final future1 = decoder.submitToken(token: 20, sequenceId: 1);
      decoder.dispatchNow();

      await expectLater(future0, throwsStateError);
      await expectLater(future1, throwsStateError);
    });

    test('Timer.run dispatches submissions', () async {
      bindings.posMax = 0;

      final future = decoder.submitToken(token: 7, sequenceId: 0);

      // Don't call dispatchNow — let Timer.run handle it.
      final result = await future;
      expect(result.batchIndex, 0);
      expect(client.batchEntries, hasLength(1));
      expect(client.batchEntries.first.token, 7);
    });

    test('dispatch resets scheduling flag for subsequent batches', () async {
      bindings.posMax = 0;

      // First batch.
      final f1 = decoder.submitToken(token: 1, sequenceId: 0);
      decoder.dispatchNow();
      await f1;

      // Second batch.
      final f2 = decoder.submitToken(token: 2, sequenceId: 0);
      decoder.dispatchNow();
      await f2;

      expect(client.decodeBatchCalls, 2);
    });

    test('empty pending list after dispatch is a no-op', () {
      // Manually dispatch with no pending submissions.
      decoder.dispatchNow();
      expect(client.decodeBatchCalls, 0);
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
