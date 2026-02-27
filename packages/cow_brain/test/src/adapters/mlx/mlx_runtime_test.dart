// Tests for MlxRuntime.
// ignore_for_file: cascade_invocations

import 'dart:convert';

import 'package:cow_brain/src/adapters/chunked_utf8.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_batch_decoder.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_client.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_handles.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_runtime.dart';
import 'package:cow_brain/src/adapters/stream_chunk.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:test/test.dart';

import '../../../fixtures/fake_mlx_bindings.dart';

const _options = MlxRuntimeOptions(
  modelPath: '/tmp/model',
  libraryPath: '/tmp/libmlx.dylib',
  contextSize: 2048,
  maxOutputTokensDefault: 100,
);

MlxRuntime _makeRuntime(
  _FakeMlxClient client,
  FakeMlxBindings bindings, {
  int modelId = 42,
}) => MlxRuntime(
  modelId: modelId,
  options: _options,
  client: client,
  bindings: bindings,
);

void main() {
  group('MlxRuntime', () {
    test('constructor creates handles and batch decoder', () {
      final bindings = FakeMlxBindings(modelFromIdResult: 5);
      final client = _FakeMlxClient();

      final runtime = _makeRuntime(client, bindings);

      expect(bindings.modelFromIdCalls, 1);
      expect(client.batchCreateCalls, 1);
      expect(runtime.batchDecoder, isA<MlxBatchDecoder>());
    });

    test('countTokens returns token count and passes addBos correctly', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()..tokenizeResult = [1, 2, 3, 4, 5];

      final runtime = _makeRuntime(client, bindings);

      final count = runtime.countTokens('hello world', addBos: true);
      expect(count, 5);
      expect(client.addSpecialCalls, [true]);
    });

    test('countTokens with addBos=false passes addSpecial=false', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()..tokenizeResult = [1, 2];

      final runtime = _makeRuntime(client, bindings);

      final count = runtime.countTokens('hi', addBos: false);
      expect(count, 2);
      expect(client.addSpecialCalls, [false]);
    });

    test('countTokens after dispose throws StateError', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient();
      final runtime = _makeRuntime(client, bindings);

      runtime.dispose();

      expect(
        () => runtime.countTokens('x', addBos: true),
        throwsStateError,
      );
    });

    test('generate streams text chunks from batchStep', () async {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()
        ..batchStepQueue.addAll([
          {0: utf8.encode('Hello')},
          {0: utf8.encode(', ')},
          {0: utf8.encode('world')},
          {0: null},
        ]);

      final runtime = _makeRuntime(client, bindings);

      final chunks = await runtime
          .generate(
            prompt: 'test',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      final text = chunks.map((c) => c.text).join();
      expect(text, 'Hello, world');
    });

    test('generate stops on null (EOG)', () async {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()
        ..batchStepQueue.addAll([
          {0: utf8.encode('tok1')},
          {0: null},
          {0: utf8.encode('tok2')},
        ]);

      final runtime = _makeRuntime(client, bindings);

      final chunks = await runtime
          .generate(
            prompt: 'test',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      final text = chunks.map((c) => c.text).join();
      // Should stop at null — tok2 should not appear.
      expect(text, 'tok1');
    });

    test('generate stops on stop sequence', () async {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()
        ..batchStepQueue.addAll([
          {0: utf8.encode('Hi')},
          {0: utf8.encode('<|end|>')},
          {0: utf8.encode('more text')},
        ]);

      final runtime = _makeRuntime(client, bindings);

      final chunks = await runtime
          .generate(
            prompt: 'test',
            stopSequences: const ['<|end|>'],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      final text = chunks.map((c) => c.text).join();
      expect(text, 'Hi');
    });

    test('generate flushes remaining text when stream ends', () async {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()
        ..batchStepQueue.addAll([
          {0: utf8.encode('partial')},
          {0: null},
        ]);

      final runtime = _makeRuntime(client, bindings);

      final chunks = await runtime
          .generate(
            prompt: 'test',
            stopSequences: const ['nevermatches'],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      final text = chunks.map((c) => c.text).join();
      expect(text, 'partial');
    });

    test('generate always tokenizes with addSpecial', () async {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()
        ..batchStepQueue.addAll([
          {0: null},
          {0: null},
        ]);

      final runtime = _makeRuntime(client, bindings);

      await runtime
          .generate(
            prompt: 'first',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      await runtime
          .generate(
            prompt: 'second',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      expect(client.addSpecialCalls, [true, true]);
    });

    test(
      'dispose frees batch decoder and second dispose is a no-op',
      () {
        final bindings = FakeMlxBindings();
        final client = _FakeMlxClient();

        final runtime = _makeRuntime(client, bindings);

        runtime.dispose();

        expect(client.batchFreeCalls, 1);

        // Second dispose — no-op.
        runtime.dispose();
        expect(client.batchFreeCalls, 1);
      },
    );

    test('reset recreates batch decoder and coordinator', () async {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()..batchStepQueue.add({0: null});

      final runtime = _makeRuntime(client, bindings);

      await runtime
          .generate(
            prompt: 'first',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      runtime.reset();

      // Old decoder freed, new one created.
      expect(client.batchFreeCalls, 1);
      expect(client.batchCreateCalls, 2);
    });

    test('reset after dispose throws StateError', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient();
      final runtime = _makeRuntime(client, bindings);

      runtime.dispose();

      expect(runtime.reset, throwsStateError);
    });

    test('generate after dispose throws StateError', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient();
      final runtime = _makeRuntime(client, bindings);

      runtime.dispose();

      expect(
        () => runtime
            .generate(
              prompt: 'test',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList(),
        throwsStateError,
      );
    });

    test('generate handles empty bytes from batchStep', () async {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()
        ..batchStepQueue.addAll([
          {0: <int>[]},
          {0: utf8.encode('ok')},
          {0: null},
        ]);

      final runtime = _makeRuntime(client, bindings);

      final chunks = await runtime
          .generate(
            prompt: 'test',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      final text = chunks.map((c) => c.text).join();
      expect(text, 'ok');
    });

    test(
      'generate handles incomplete UTF-8 that leaves decodedChunks empty',
      () async {
        final bindings = FakeMlxBindings();
        final client = _FakeMlxClient()
          ..batchStepQueue.addAll([
            {
              0: [0xC2],
            }, // incomplete UTF-8
            {0: null},
          ]);

        final runtime = _makeRuntime(client, bindings);

        final chunks = await runtime
            .generate(
              prompt: 'test',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList();

        expect(chunks, isA<List<StreamChunk>>());
      },
    );

    test(
      'generate handles split multi-byte UTF-8',
      () async {
        final bindings = FakeMlxBindings();
        // U+00A9 = © = C2 A9 in UTF-8, split across two steps.
        final client = _FakeMlxClient()
          ..batchStepQueue.addAll([
            {
              0: [0xC2],
            },
            {
              0: [0xA9],
            },
            {0: utf8.encode('!')},
            {0: null},
          ]);

        final runtime = _makeRuntime(client, bindings);

        final chunks = await runtime
            .generate(
              prompt: 'test',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList();

        final text = chunks.map((c) => c.text).join();
        expect(text, contains('©'));
        expect(text, contains('!'));
      },
    );

    test(
      'generate flushes remaining decoded chunks in finally block',
      () async {
        final bindings = FakeMlxBindings();
        final client = _FakeMlxClient()
          ..batchStepQueue.addAll([
            {0: utf8.encode('hi')},
            {
              0: [0xC2],
            }, // incomplete — buffered
            {0: null},
          ]);

        final runtime = _makeRuntime(client, bindings);

        final chunks = await runtime
            .generate(
              prompt: 'test',
              stopSequences: const ['nevermatches'],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList();

        final text = chunks.map((c) => c.text).join();
        expect(text, startsWith('hi'));
      },
    );

    test('yields heartbeat after consecutive empty tokens', () async {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()
        ..batchStepQueue.addAll([
          ...List.generate(17, (_) => {0: <int>[]}),
          {0: null},
        ]);

      final runtime = MlxRuntime(
        modelId: 42,
        options: const MlxRuntimeOptions(
          modelPath: '/tmp/model',
          libraryPath: '/tmp/libmlx.dylib',
          contextSize: 2048,
          maxOutputTokensDefault: 20,
        ),
        client: client,
        bindings: bindings,
      );

      final chunks = await runtime
          .generate(
            prompt: 'test',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      final heartbeats = chunks.where((c) => c.text.isEmpty).toList();
      expect(heartbeats, isNotEmpty);
    });
  });

  group('mlx helpers', () {
    test('drains multiple decoded chunks via join path', () {
      final chunks = <String>['a', 'b'];
      final piece = drainDecodedChunks(chunks);
      expect(piece, 'ab');
      expect(chunks, isEmpty);
    });

    test('chunked string sink writeAll and writeln', () {
      final chunks = <String>[];
      final sink = ChunkedStringSink(chunks);
      sink.writeAll([1, null, 'b'], ',');
      sink.writeln('x');
      sink.writeln();
      expect(chunks, ['1', ',', ',', 'b', 'x', '\n', '\n']);
    });

    test('chunked string sink writeCharCode', () {
      final chunks = <String>[];
      final sink = ChunkedStringSink(chunks);
      sink.writeCharCode(65); // 'A'
      expect(chunks, ['A']);
    });
  });

  group('multi-sequence', () {
    test('createSequence registers new sequence', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient();
      final runtime = _makeRuntime(client, bindings);

      runtime.createSequence(1);

      // Should not throw when generating on sequence 1.
      expect(
        () => runtime.createSequence(1),
        throwsStateError,
      );
    });

    test('createSequence throws when sequence already exists', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient();
      final runtime = _makeRuntime(client, bindings);

      expect(
        () => runtime.createSequence(0),
        throwsStateError,
      );
    });

    test('destroySequence removes sequence', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient();
      final runtime = _makeRuntime(client, bindings);

      runtime.createSequence(1);
      runtime.destroySequence(1);

      // Should throw since it's been removed.
      expect(
        () => runtime.destroySequence(1),
        throwsStateError,
      );
    });

    test('destroySequence throws for unknown sequence', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient();
      final runtime = _makeRuntime(client, bindings);

      expect(
        () => runtime.destroySequence(99),
        throwsStateError,
      );
    });

    test('forkSequence registers target sequence', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient();
      final runtime = _makeRuntime(client, bindings);

      runtime.forkSequence(source: 0, target: 1);

      // Target should exist now.
      expect(
        () => runtime.createSequence(1),
        throwsStateError,
      );
    });

    test('forkSequence throws when source does not exist', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient();
      final runtime = _makeRuntime(client, bindings);

      expect(
        () => runtime.forkSequence(source: 99, target: 1),
        throwsStateError,
      );
    });

    test('forkSequence throws when target already exists', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient();
      final runtime = _makeRuntime(client, bindings);

      expect(
        () => runtime.forkSequence(source: 0, target: 0),
        throwsStateError,
      );
    });

    test('generate on specific sequenceId works', () async {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()
        ..batchStepQueue.addAll([
          {1: utf8.encode('hi')},
          {1: null},
        ]);
      final runtime = _makeRuntime(client, bindings);

      runtime.createSequence(1);

      final chunks = await runtime
          .generate(
            prompt: 'test',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
            sequenceId: 1,
          )
          .toList();

      final text = chunks.map((c) => c.text).join();
      expect(text, 'hi');
      // addAndPrefill should have been called for seq 1.
      expect(client.batchAddSequenceCalls, 1);
      expect(client.lastBatchAddSeqId, 1);
    });

    test('generate on non-existent sequenceId throws', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient();
      final runtime = _makeRuntime(client, bindings);

      expect(
        () => runtime
            .generate(
              prompt: 'test',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
              sequenceId: 99,
            )
            .toList(),
        throwsStateError,
      );
    });

    test('reset clears sequences and recreates decoder', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient();
      final runtime = _makeRuntime(client, bindings);

      runtime.createSequence(1);
      runtime.reset();

      // Sequence 1 should be gone.
      expect(
        () => runtime.destroySequence(1),
        throwsStateError,
      );
      // Sequence 0 should still exist.
      expect(
        () => runtime.createSequence(0),
        throwsStateError,
      );
      // Decoder should have been recreated.
      expect(client.batchFreeCalls, 1);
      expect(client.batchCreateCalls, 2);
    });
  });

  group('MlxBatchCoordinator', () {
    test('awaitStep coalesces and dispatches via Timer.run', () async {
      final client = _FakeMlxClient()
        ..batchStepQueue.add({0: utf8.encode('hello')});
      final bindings = FakeMlxBindings();
      final decoder = MlxBatchDecoder(
        client: client,
        handles: MlxHandles.fromModelId(modelId: 1, bindings: bindings),
        maxTokens: 512,
      );
      final coordinator = MlxBatchCoordinator(decoder: decoder);

      coordinator.addAndPrefill(0, [1, 2, 3], const SamplingOptions());

      final result = await coordinator.awaitStep(0);

      expect(result, utf8.encode('hello'));
      decoder.dispose();
    });

    test('removeSequence is idempotent', () {
      final client = _FakeMlxClient();
      final bindings = FakeMlxBindings();
      final decoder = MlxBatchDecoder(
        client: client,
        handles: MlxHandles.fromModelId(modelId: 1, bindings: bindings),
        maxTokens: 512,
      );
      final coordinator = MlxBatchCoordinator(decoder: decoder);

      coordinator.addAndPrefill(0, [1, 2, 3], const SamplingOptions());
      coordinator.removeSequence(0);
      // Second call should be a no-op.
      coordinator.removeSequence(0);

      expect(client.batchRemoveSequenceCalls, 1);
      decoder.dispose();
    });

    test('EOG automatically removes sequence from batch', () async {
      final client = _FakeMlxClient()..batchStepQueue.add({0: null});
      final bindings = FakeMlxBindings();
      final decoder = MlxBatchDecoder(
        client: client,
        handles: MlxHandles.fromModelId(modelId: 1, bindings: bindings),
        maxTokens: 512,
      );
      final coordinator = MlxBatchCoordinator(decoder: decoder);

      coordinator.addAndPrefill(0, [1, 2, 3], const SamplingOptions());

      final result = await coordinator.awaitStep(0);
      expect(result, isNull);
      expect(coordinator.activeCount, 0);

      // removeSequence after EOG should be no-op.
      coordinator.removeSequence(0);
      expect(client.batchRemoveSequenceCalls, 1);
      decoder.dispose();
    });

    test('dispatchNow dispatches synchronously', () async {
      final client = _FakeMlxClient()
        ..batchStepQueue.add({0: utf8.encode('sync')});
      final bindings = FakeMlxBindings();
      final decoder = MlxBatchDecoder(
        client: client,
        handles: MlxHandles.fromModelId(modelId: 1, bindings: bindings),
        maxTokens: 512,
      );
      final coordinator = MlxBatchCoordinator(decoder: decoder);

      coordinator.addAndPrefill(0, [1, 2, 3], const SamplingOptions());

      final future = coordinator.awaitStep(0);
      coordinator.dispatchNow();

      final result = await future;
      expect(result, utf8.encode('sync'));
      decoder.dispose();
    });

    test('error in step propagates to all waiters', () async {
      final client = _FakeMlxClient()..batchStepShouldThrow = true;
      final bindings = FakeMlxBindings();
      final decoder = MlxBatchDecoder(
        client: client,
        handles: MlxHandles.fromModelId(modelId: 1, bindings: bindings),
        maxTokens: 512,
      );
      final coordinator = MlxBatchCoordinator(decoder: decoder);

      coordinator.addAndPrefill(0, [1, 2, 3], const SamplingOptions());

      expect(coordinator.awaitStep(0), throwsStateError);
      decoder.dispose();
    });
  });
}

final class _FakeMlxClient implements MlxClientApi {
  _FakeMlxClient();

  List<int> tokenizeResult = const [1, 2, 3];
  final List<bool> addSpecialCalls = [];
  int createContextCalls = 0;
  int createContextResult = 10;
  int resetContextCalls = 0;
  int disposeCalls = 0;

  @override
  List<int> tokenize(
    MlxHandles handles,
    String text, {
    bool addSpecial = true,
  }) {
    addSpecialCalls.add(addSpecial);
    return tokenizeResult;
  }

  @override
  int createContext(MlxHandles handles, int maxTokens) {
    createContextCalls++;
    return createContextResult;
  }

  @override
  void resetContext(MlxHandles handles, int maxTokens) {
    resetContextCalls++;
    handles.contextHandle = createContext(handles, maxTokens);
  }

  @override
  bool isEog(MlxHandles handles, int token) => false;

  @override
  void generateBegin(
    MlxHandles handles,
    List<int> tokens,
    SamplingOptions options, {
    required int contextHandle,
  }) {}

  @override
  List<int>? generateNext(
    MlxHandles handles, {
    required int contextHandle,
    int bufferSize = 256,
  }) => null;

  @override
  void dispose(MlxHandles handles) {
    disposeCalls++;
  }

  @override
  MlxHandles loadModel({
    required String modelPath,
    MlxModelLoadProgressCallback? onProgress,
  }) => throw UnimplementedError();

  // -- Batch API --

  int batchCreateCalls = 0;
  int batchFreeCalls = 0;
  int batchAddSequenceCalls = 0;
  int? lastBatchAddSeqId;
  int batchPrefillCalls = 0;
  int batchRemoveSequenceCalls = 0;
  bool batchStepShouldThrow = false;

  /// Queue of step results. Each entry maps seqId → bytes (null = EOG).
  final List<Map<int, List<int>?>> batchStepQueue = [];

  @override
  int batchCreate(MlxHandles handles, int maxTokens) {
    batchCreateCalls++;
    return 1;
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
    lastBatchAddSeqId = seqId;
  }

  @override
  int batchPrefill(
    MlxHandles handles,
    int batchHandle,
    SamplingOptions options,
  ) {
    batchPrefillCalls++;
    return 1;
  }

  @override
  Map<int, List<int>?> batchStep(
    MlxHandles handles,
    int batchHandle, {
    int maxSeqs = 16,
    int bufferSize = 4096,
  }) {
    if (batchStepShouldThrow) {
      throw StateError('batchStep failed');
    }
    if (batchStepQueue.isEmpty) return {};
    return batchStepQueue.removeAt(0);
  }

  @override
  void batchRemoveSequence(
    MlxHandles handles,
    int batchHandle,
    int seqId,
  ) {
    batchRemoveSequenceCalls++;
  }

  @override
  int batchActiveCount(MlxHandles handles, int batchHandle) => 0;
}
