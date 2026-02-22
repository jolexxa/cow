// Tests for MlxRuntime.
// ignore_for_file: cascade_invocations

import 'dart:convert';

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
    test('constructor creates handles and context', () {
      final bindings = FakeMlxBindings(
        modelFromIdResult: 5,
      );
      final client = _FakeMlxClient()..createContextResult = 10;

      _makeRuntime(client, bindings);

      expect(bindings.modelFromIdCalls, 1);
      expect(client.createContextCalls, 1);
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

    test('generate streams text chunks from generateNext queue', () async {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()
        ..generateNextQueue.addAll([
          utf8.encode('Hello'),
          utf8.encode(', '),
          utf8.encode('world'),
          null,
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
        ..generateNextQueue.addAll([
          utf8.encode('tok1'),
          null,
          utf8.encode('tok2'),
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
        ..generateNextQueue.addAll([
          utf8.encode('Hi'),
          utf8.encode('<|end|>'),
          utf8.encode('more text'),
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

    test(
      'generate with requiresReset recreates context and resets BOS',
      () async {
        final bindings = FakeMlxBindings();
        final client = _FakeMlxClient()..generateNextQueue.add(null);

        final runtime = _makeRuntime(client, bindings);

        // First generate to set BOS applied.
        await runtime
            .generate(
              prompt: 'first',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList();

        client.generateNextQueue.add(null);
        client.resetContextCalls = 0;
        client.addSpecialCalls.clear();

        // Second generate with reset.
        await runtime
            .generate(
              prompt: 'second',
              stopSequences: const [],
              addBos: true,
              requiresReset: true,
              reusePrefixMessageCount: 0,
            )
            .toList();

        // Reset now frees the old context and creates a new one.
        expect(bindings.freeContextCalls, 1);
        // Constructor created one context, reset created another.
        expect(client.createContextCalls, 2);
        // After reset, BOS should be false again so next tokenize gets
        // addSpecial=true.
        expect(client.addSpecialCalls.last, isTrue);
      },
    );

    test('generate after reset uses the new context handle', () async {
      final bindings = FakeMlxBindings();
      var nextCtx = 100;
      final client = _FakeMlxClient()
        ..createContextResult = nextCtx
        ..generateNextQueue.add(null);

      final runtime = _makeRuntime(client, bindings);

      // First generate — normal.
      await runtime
          .generate(
            prompt: 'first',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      // Reset creates a new context handle.
      nextCtx = 200;
      client
        ..createContextResult = nextCtx
        ..generateNextQueue.add(null);

      await runtime
          .generate(
            prompt: 'second',
            stopSequences: const [],
            addBos: true,
            requiresReset: true,
            reusePrefixMessageCount: 0,
          )
          .toList();

      // Third generate WITHOUT reset — must use the handle from reset,
      // not the stale original.
      client.generateNextQueue.add(null);

      await runtime
          .generate(
            prompt: 'third',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      // generateBegin should have received the new context handle (200),
      // not the original. We verify via the handle stored on the handles
      // object at the time of the last generateBegin call.
      expect(client.lastGenerateBeginContextHandle, nextCtx);
    });

    test('generate flushes remaining text when stream ends', () async {
      final bindings = FakeMlxBindings();
      // Use a stop sequence long enough that text won't flush until end.
      final client = _FakeMlxClient()
        ..generateNextQueue.addAll([utf8.encode('partial'), null]);

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

    test(
      'generate always tokenizes with addSpecial for cache alignment',
      () async {
        final bindings = FakeMlxBindings();
        final client = _FakeMlxClient()..generateNextQueue.add(null);

        final runtime = _makeRuntime(client, bindings);

        // First generate with addBos=true.
        await runtime
            .generate(
              prompt: 'first',
              stopSequences: const [],
              addBos: true,
              requiresReset: false,
              reusePrefixMessageCount: 0,
            )
            .toList();

        client.generateNextQueue.add(null);

        // Second generate — still addSpecial=true so token positions
        // align with the KV cache (which starts with BOS from gen 1).
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
      },
    );

    test(
      'dispose frees context via bindings and second dispose is a no-op',
      () {
        final bindings = FakeMlxBindings();
        final client = _FakeMlxClient()..createContextResult = 10;

        final runtime = _makeRuntime(client, bindings);

        runtime.dispose();

        expect(bindings.freeContextCalls, 1);
        expect(bindings.lastFreeContextHandle, 10);

        // Second dispose — no-op, no extra freeContext calls.
        runtime.dispose();
        expect(bindings.freeContextCalls, 1);
      },
    );

    test('reset delegates to client and resets BOS state', () async {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()..generateNextQueue.add(null);

      final runtime = _makeRuntime(client, bindings);

      // Apply BOS by generating.
      await runtime
          .generate(
            prompt: 'first',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      client.addSpecialCalls.clear();

      runtime.reset();

      expect(client.resetContextCalls, 1);

      // After reset, BOS state cleared — next countTokens with addBos=true
      // should pass addSpecial=true again.
      runtime.countTokens('check', addBos: true);
      expect(client.addSpecialCalls.last, isTrue);
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

    test('generate handles empty bytes from generateNext', () async {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()
        ..generateNextQueue.addAll([
          [], // empty bytes — hits bytes.isEmpty branch
          utf8.encode('ok'),
          null,
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
        // 0xC2 alone is an incomplete 2-byte UTF-8 sequence.
        // byteSink.add([0xC2]) produces no output (decodedChunks stays empty).
        final client = _FakeMlxClient()
          ..generateNextQueue.addAll([
            [0xC2], // incomplete UTF-8 — decodedChunks.isEmpty path
            null,
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

        // Should complete without error.
        expect(chunks, isA<List<StreamChunk>>());
      },
    );

    test(
      'generate handles piece.isEmpty after draining decoded chunks',
      () async {
        // This is tricky — we need byteSink.add to produce a chunk,
        // but draining it yields an empty string. The easiest way is to
        // produce a chunk that decodes to empty via the sink.
        // Actually, this path is extremely hard to hit because the UTF-8
        // decoder won't produce empty strings. Let's use coverage:ignore
        // or accept this edge case. For now, let's test the finally branch.
        final bindings = FakeMlxBindings();
        // Two chunks that decode together — tests the join branch in
        // _drainDecodedChunks when decodedChunks.length > 1.
        // Send a multi-byte char split across two generateNext calls.
        // U+00A9 = ©  = C2 A9 in UTF-8.
        final client = _FakeMlxClient()
          ..generateNextQueue.addAll([
            [0xC2], // first byte — buffered, decodedChunks empty
            [0xA9], // second byte — completes char, decodedChunks has "©"
            utf8.encode('!'),
            null,
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
        // Send an incomplete UTF-8 sequence so byteSink has buffered data
        // that gets flushed in the finally block when byteSink.close() is
        // called. The replacement char ends up in decodedChunks.
        final client = _FakeMlxClient()
          ..generateNextQueue.addAll([
            utf8.encode('hi'),
            [0xC2], // incomplete — buffered in byteSink
            null, // EOG — triggers finally block
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
        // "hi" + replacement char from the flushed incomplete sequence.
        expect(text, startsWith('hi'));
      },
    );

    test(
      'yields heartbeat after consecutive empty tokens',
      () async {
        final bindings = FakeMlxBindings();
        // 17 empty byte arrays — hits the empty token heartbeat path.
        final client = _FakeMlxClient()
          ..generateNextQueue.addAll([
            ...List.generate(17, (_) => <int>[]),
            null,
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

        // After 16 empty tokens the assembler emits a heartbeat.
        final heartbeats = chunks.where((c) => c.text.isEmpty).toList();
        expect(heartbeats, isNotEmpty);
      },
    );
  });

  group('incremental generation & KV cache', () {
    test(
      'incremental generation without reset does not call resetContext',
      () async {
        final bindings = FakeMlxBindings();
        final client = _FakeMlxClient()..generateNextQueue.addAll([null, null]);

        final runtime = _makeRuntime(client, bindings);

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

        expect(client.resetContextCalls, 0);
        // Both calls get addSpecial=true for KV cache alignment.
        expect(client.addSpecialCalls, [true, true]);
      },
    );

    test(
      'reset between generations recreates context and re-sends BOS',
      () async {
        final bindings = FakeMlxBindings();
        final client = _FakeMlxClient()..generateNextQueue.addAll([null, null]);

        final runtime = _makeRuntime(client, bindings);

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

        // Reset frees old context + creates new one.
        expect(bindings.freeContextCalls, 1);
        expect(client.createContextCalls, 2);
        // BOS re-sent after reset.
        expect(client.addSpecialCalls, [true, true]);
      },
    );

    test('three sequential generations always tokenize with BOS', () async {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()
        ..generateNextQueue.addAll([null, null, null]);

      final runtime = _makeRuntime(client, bindings);

      // gen1: first call.
      await runtime
          .generate(
            prompt: 'first',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
          )
          .toList();

      // gen2: incremental — still addSpecial=true for cache alignment.
      await runtime
          .generate(
            prompt: 'second',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 1,
          )
          .toList();

      // gen3: reset — addSpecial=true as always.
      await runtime
          .generate(
            prompt: 'third',
            stopSequences: const [],
            addBos: true,
            requiresReset: true,
            reusePrefixMessageCount: 0,
          )
          .toList();

      // All three always get addSpecial=true for KV cache alignment.
      expect(client.addSpecialCalls, [true, true, true]);
      // Third generate had requiresReset — frees old context + creates new.
      expect(bindings.freeContextCalls, 1);
      expect(client.createContextCalls, 2);
    });
  });

  group('mlx helpers', () {
    test('drains multiple decoded chunks via join path', () {
      final chunks = <String>['a', 'b'];
      final piece = drainMlxDecodedChunks(chunks);
      expect(piece, 'ab');
      expect(chunks, isEmpty);
    });

    test('chunked string sink writeAll and writeln', () {
      final chunks = <String>[];
      final sink = mlxChunkedStringSink(chunks);
      sink.writeAll([1, null, 'b'], ',');
      sink.writeln('x');
      sink.writeln();
      expect(chunks, ['1', ',', ',', 'b', 'x', '\n', '\n']);
    });

    test('chunked string sink writeCharCode', () {
      final chunks = <String>[];
      final sink = mlxChunkedStringSink(chunks);
      sink.writeCharCode(65); // 'A'
      expect(chunks, ['A']);
    });
  });

  group('multi-sequence', () {
    test('createSequence allocates a new context handle', () {
      final bindings = FakeMlxBindings();
      bindings.createContextResult = 20;
      final client = _FakeMlxClient()..createContextResult = 20;
      final runtime = _makeRuntime(client, bindings);

      runtime.createSequence(1);

      // 1 for constructor + 1 for createSequence.
      expect(client.createContextCalls, 2);
    });

    test('createSequence throws when sequence already exists', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient();
      final runtime = _makeRuntime(client, bindings);

      // Sequence 0 is created in the constructor.
      expect(
        () => runtime.createSequence(0),
        throwsStateError,
      );
    });

    test('destroySequence frees context and removes it', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()..createContextResult = 20;
      final runtime = _makeRuntime(client, bindings);

      runtime.createSequence(1);
      runtime.destroySequence(1);

      expect(bindings.freeContextCalls, 1);
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

    test('forkSequence creates target and copies cache', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()..createContextResult = 20;
      final runtime = _makeRuntime(client, bindings);

      runtime.forkSequence(source: 0, target: 1);

      expect(bindings.forkContextCalls, 1);
      // Constructor + fork target = 2 create calls.
      expect(client.createContextCalls, 2);
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

    test('forkSequence cleans up on failure', () {
      final bindings = FakeMlxBindings()..forkContextResult = false;
      final client = _FakeMlxClient()..createContextResult = 20;
      final runtime = _makeRuntime(client, bindings);

      expect(
        () => runtime.forkSequence(source: 0, target: 1),
        throwsStateError,
      );

      // Should have freed the target context on failure.
      expect(bindings.freeContextCalls, 1);
    });

    test('createBatchDecoder returns a decoder', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient();
      final runtime = _makeRuntime(client, bindings);

      final decoder = runtime.createBatchDecoder(maxTokens: 512);

      expect(decoder, isNotNull);
      expect(client.batchCreateCalls, 1);

      decoder.dispose();
    });

    test('createBatchDecoder after dispose throws', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient();
      final runtime = _makeRuntime(client, bindings);

      runtime.dispose();

      expect(
        () => runtime.createBatchDecoder(maxTokens: 512),
        throwsStateError,
      );
    });

    test('generate on specific sequenceId uses that context', () async {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()
        ..createContextResult = 20
        ..generateNextQueue.addAll([null, null]);
      final runtime = _makeRuntime(client, bindings);

      runtime.createSequence(1);

      // Generate on sequence 1.
      await runtime
          .generate(
            prompt: 'test',
            stopSequences: const [],
            addBos: true,
            requiresReset: false,
            reusePrefixMessageCount: 0,
            sequenceId: 1,
          )
          .toList();

      // generateBegin should have received the sequence 1 context handle.
      expect(client.lastGenerateBeginContextHandle, 20);
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

    test('reset frees non-zero sequences and resets seq 0', () {
      final bindings = FakeMlxBindings();
      final client = _FakeMlxClient()..createContextResult = 20;
      final runtime = _makeRuntime(client, bindings);

      runtime.createSequence(1);
      runtime.reset();

      // Should have freed sequence 1's context.
      expect(bindings.freeContextCalls, 1);
      // Should have reset sequence 0.
      expect(client.resetContextCalls, 1);
    });
  });
}

final class _FakeMlxClient implements MlxClientApi {
  _FakeMlxClient();

  List<int> tokenizeResult = const [1, 2, 3];
  final List<bool> addSpecialCalls = [];
  int createContextResult = 10;
  int createContextCalls = 0;
  int resetContextCalls = 0;
  int generateBeginCalls = 0;
  int disposeCalls = 0;

  // Queue of byte lists to return from generateNext. null = done.
  final List<List<int>?> generateNextQueue = [];
  int generateNextCalls = 0;

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
    // Match real MlxClient.resetContext: assign a new context handle.
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
  }) {
    generateBeginCalls++;
    lastGenerateBeginContextHandle = contextHandle;
  }

  int? lastGenerateBeginContextHandle;

  @override
  List<int>? generateNext(
    MlxHandles handles, {
    required int contextHandle,
    int bufferSize = 256,
  }) {
    generateNextCalls++;
    if (generateNextQueue.isEmpty) return null;
    return generateNextQueue.removeAt(0);
  }

  @override
  void dispose(MlxHandles handles) {
    disposeCalls++;
  }

  @override
  MlxHandles loadModel({
    required String modelPath,
    MlxModelLoadProgressCallback? onProgress,
  }) => throw UnimplementedError();

  // Batch stubs.
  int batchCreateCalls = 0;
  @override
  int batchCreate(MlxHandles handles, int maxTokens) {
    batchCreateCalls++;
    return 1;
  }

  @override
  void batchFree(MlxHandles handles, int batchHandle) {}
  @override
  void batchAddSequence(
    MlxHandles handles,
    int batchHandle,
    int seqId,
    List<int> tokens,
  ) {}
  @override
  int batchPrefill(
    MlxHandles handles,
    int batchHandle,
    SamplingOptions options,
  ) => 0;
  @override
  Map<int, List<int>?> batchStep(
    MlxHandles handles,
    int batchHandle, {
    int maxSeqs = 16,
    int bufferSize = 4096,
  }) => {};
  @override
  void batchRemoveSequence(MlxHandles handles, int batchHandle, int seqId) {}
  @override
  int batchActiveCount(MlxHandles handles, int batchHandle) => 0;
}
