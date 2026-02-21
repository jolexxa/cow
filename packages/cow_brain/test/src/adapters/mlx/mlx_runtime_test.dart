// Tests for MlxRuntime.
// ignore_for_file: cascade_invocations

import 'dart:convert';

import 'package:cow_brain/src/adapters/mlx/mlx_client.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_handles.dart';
import 'package:cow_brain/src/adapters/mlx/mlx_runtime.dart';
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
      'generate with requiresReset calls resetContext and resets BOS',
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

        expect(client.resetContextCalls, 1);
        // After reset, BOS should be false again so next tokenize gets
        // addSpecial=true.
        expect(client.addSpecialCalls.last, isTrue);
      },
    );

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
  });

  group('incremental generation & KV cache', () {
    test(
      'incremental generation without reset does not call resetContext',
      () async {
        final bindings = FakeMlxBindings();
        final client = _FakeMlxClient()
          ..generateNextQueue.addAll([null, null]);

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
      'reset between generations calls resetContext and re-sends BOS',
      () async {
        final bindings = FakeMlxBindings();
        final client = _FakeMlxClient()
          ..generateNextQueue.addAll([null, null]);

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

        expect(client.resetContextCalls, 1);
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
  }

  @override
  bool isEog(MlxHandles handles, int token) => false;

  @override
  void generateBegin(
    MlxHandles handles,
    List<int> tokens,
    SamplingOptions options,
  ) {
    generateBeginCalls++;
  }

  @override
  List<int>? generateNext(MlxHandles handles, {int bufferSize = 256}) {
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
}
