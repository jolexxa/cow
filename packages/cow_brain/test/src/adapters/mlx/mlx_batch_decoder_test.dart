// Tests for MlxBatchDecoder

import 'package:cow_brain/src/adapters/mlx/mlx_batch_decoder.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_client.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_handles.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

import '../../../fixtures/fake_mlx_bindings.dart';

void main() {
  late FakeMlxBindings bindings;
  late _FakeBatchMlxClient client;
  late MlxHandles handles;

  setUp(() {
    bindings = FakeMlxBindings();
    client = _FakeBatchMlxClient();
    handles = MlxHandles(
      bindings: bindings,
      modelHandle: 1,
      contextHandle: 10,
    );
  });

  group('MlxBatchDecoder', () {
    test('constructor creates a batch via client', () {
      final decoder = MlxBatchDecoder(
        client: client,
        handles: handles,
        maxTokens: 512,
      );

      expect(client.batchCreateCalls, 1);
      expect(client.lastBatchCreateMaxTokens, 512);

      decoder.dispose();
    });

    test('addSequence delegates to client', () {
      final decoder =
          MlxBatchDecoder(
              client: client,
              handles: handles,
              maxTokens: 512,
            )
            ..addSequence(0, [1, 2, 3])
            ..addSequence(1, [4, 5, 6]);

      expect(client.batchAddSequenceCalls, 2);
      expect(client.addedSequences.length, 2);
      expect(client.addedSequences[0].seqId, 0);
      expect(client.addedSequences[0].tokens, [1, 2, 3]);
      expect(client.addedSequences[1].seqId, 1);
      expect(client.addedSequences[1].tokens, [4, 5, 6]);

      decoder.dispose();
    });

    test('prefill delegates to client and returns active count', () {
      final decoder = MlxBatchDecoder(
        client: client,
        handles: handles,
        maxTokens: 512,
      );

      client.batchPrefillResult = 3;
      final count = decoder.prefill(const SamplingOptions());

      expect(count, 3);
      expect(client.batchPrefillCalls, 1);

      decoder.dispose();
    });

    test('step returns per-sequence token bytes', () {
      final decoder = MlxBatchDecoder(
        client: client,
        handles: handles,
        maxTokens: 512,
      );

      client.batchStepResult = {
        0: [72, 101, 108, 108, 111], // "Hello"
        1: [87, 111, 114, 108, 100], // "World"
      };

      final result = decoder.step();

      expect(result, {
        0: [72, 101, 108, 108, 111],
        1: [87, 111, 114, 108, 100],
      });

      decoder.dispose();
    });

    test('step returns null for EOG sequences', () {
      final decoder = MlxBatchDecoder(
        client: client,
        handles: handles,
        maxTokens: 512,
      );

      client.batchStepResult = {
        0: null,
        1: [65],
      };
      final result = decoder.step();

      expect(result[0], isNull);
      expect(result[1], [65]);

      decoder.dispose();
    });

    test('removeSequence delegates to client', () {
      final decoder = MlxBatchDecoder(
        client: client,
        handles: handles,
        maxTokens: 512,
      )..removeSequence(42);

      expect(client.batchRemoveSequenceCalls, 1);
      expect(client.lastRemovedSeqId, 42);

      decoder.dispose();
    });

    test('activeCount returns count from client', () {
      final decoder = MlxBatchDecoder(
        client: client,
        handles: handles,
        maxTokens: 512,
      );

      client.batchActiveCountResult = 5;
      expect(decoder.activeCount, 5);

      decoder.dispose();
    });

    test('dispose frees the batch', () {
      MlxBatchDecoder(
        client: client,
        handles: handles,
        maxTokens: 512,
      ).dispose();
      expect(client.batchFreeCalls, 1);
    });
  });
}

// ---------------------------------------------------------------------------
// Fake client that tracks batch calls
// ---------------------------------------------------------------------------

final class _FakeBatchMlxClient implements MlxClientApi {
  int batchCreateCalls = 0;
  int? lastBatchCreateMaxTokens;
  int batchCreateResult_ = 1;
  int batchFreeCalls = 0;
  int batchAddSequenceCalls = 0;
  final List<({int seqId, List<int> tokens})> addedSequences = [];
  int batchPrefillCalls = 0;
  int batchPrefillResult = 0;
  int batchStepCalls = 0;
  Map<int, List<int>?> batchStepResult = {};
  int batchRemoveSequenceCalls = 0;
  int? lastRemovedSeqId;
  int batchActiveCountResult = 0;

  @override
  int batchCreate(MlxHandles handles, int maxTokens) {
    batchCreateCalls++;
    lastBatchCreateMaxTokens = maxTokens;
    return batchCreateResult_;
  }

  @override
  void batchFree(MlxHandles handles, int batchHandle) {
    batchFreeCalls++;
  }

  @override
  void batchAddSequence(
    MlxHandles handles,
    int batchHandle,
    int seqId,
    List<int> tokens,
  ) {
    batchAddSequenceCalls++;
    addedSequences.add((seqId: seqId, tokens: tokens));
  }

  @override
  int batchPrefill(
    MlxHandles handles,
    int batchHandle,
    SamplingOptions options,
  ) {
    batchPrefillCalls++;
    return batchPrefillResult;
  }

  @override
  Map<int, List<int>?> batchStep(
    MlxHandles handles,
    int batchHandle, {
    int maxSeqs = 16,
    int bufferSize = 4096,
  }) {
    batchStepCalls++;
    return batchStepResult;
  }

  @override
  void batchRemoveSequence(MlxHandles handles, int batchHandle, int seqId) {
    batchRemoveSequenceCalls++;
    lastRemovedSeqId = seqId;
  }

  @override
  int batchActiveCount(MlxHandles handles, int batchHandle) =>
      batchActiveCountResult;

  // -- Non-batch stubs --
  @override
  MlxHandles loadModel({
    required String modelPath,
    MlxModelLoadProgressCallback? onProgress,
  }) => throw UnimplementedError();
  @override
  List<int> tokenize(
    MlxHandles handles,
    String text, {
    bool addSpecial = true,
  }) => [1, 2, 3];
  @override
  int createContext(MlxHandles handles, int maxTokens) => 10;
  @override
  void resetContext(MlxHandles handles, int maxTokens) {}
  @override
  bool isEog(MlxHandles handles, int token) => false;
  @override
  void generateBegin(
    MlxHandles handles,
    List<int> tokens,
    SamplingOptions options,
  ) {}
  @override
  List<int>? generateNext(MlxHandles handles, {int bufferSize = 256}) => null;
  @override
  void dispose(MlxHandles handles) {}
}
