// Cascade style doesn't improve readability in tests with sequential steps.
// ignore_for_file: cascade_invocations

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:cow_brain/src/isolate/models.dart';
import 'package:cow_brain/src/model_server/model_server.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_bindings.dart';

void main() {
  group('ModelServerIsolateTestHarness', () {
    late ReceivePort receivePort;
    late StreamController<Map<String, Object?>> responseController;
    late FakeLlamaBindings bindings;
    late _FakeLlamaClient fakeClient;

    setUp(() {
      receivePort = ReceivePort();
      responseController = StreamController<Map<String, Object?>>.broadcast();

      receivePort.listen((message) {
        if (message is Map) {
          responseController.add(Map<String, Object?>.from(message));
        }
      });

      bindings = FakeLlamaBindings();
      fakeClient = _FakeLlamaClient(bindings);

      // Override the openBindings for LlamaClient static method.
      LlamaClient.openBindings = ({required String libraryPath}) => bindings;
    });

    tearDown(() async {
      receivePort.close();
      await responseController.close();
      LlamaClient.openBindings = LlamaBindingsLoader.open;
      modelServerClientFactoryOverride = null;
    });

    ModelServerIsolateTestHarness createHarness({
      LlamaClientFactory? clientFactory,
    }) {
      return ModelServerIsolateTestHarness(
        receivePort.sendPort,
        clientFactory: clientFactory,
      );
    }

    Future<ModelServerResponse> expectResponse() async {
      final json = await responseController.stream.first;
      return ModelServerResponse.fromJson(json);
    }

    Future<List<ModelServerResponse>> collectResponses(int count) async {
      return responseController.stream
          .take(count)
          .map(ModelServerResponse.fromJson)
          .toList();
    }

    test(
      'load_model initializes backend and sends ModelLoadedResponse',
      () async {
        final harness = createHarness(
          clientFactory: ({required libraryPath}) => fakeClient,
        );

        harness.handleMessage(
          const LoadModelRequest(
            modelPath: '/models/test.gguf',
            libraryPath: '/lib/libllama.so',
          ).toJson(),
        );

        // Expect progress + loaded responses.
        final responses = await collectResponses(2);

        final loaded = responses.whereType<ModelLoadedResponse>().first;
        expect(loaded.modelPath, '/models/test.gguf');
        expect(loaded.modelPointer, fakeClient.lastHandles!.model.address);
      },
    );

    test('load_model sends progress callbacks', () async {
      final harness = createHarness(
        clientFactory: ({required libraryPath}) => fakeClient,
      );

      harness.handleMessage(
        const LoadModelRequest(
          modelPath: '/models/test.gguf',
          libraryPath: '/lib/libllama.so',
        ).toJson(),
      );

      // Expect progress + loaded responses.
      final responses = await collectResponses(2);

      final progressResponses = responses
          .whereType<LoadProgressResponse>()
          .toList();
      expect(progressResponses, hasLength(1));
      expect(progressResponses.first.progress, 0.5);

      final loadedResponses = responses
          .whereType<ModelLoadedResponse>()
          .toList();
      expect(loadedResponses, hasLength(1));
    });

    test('load_model returns cached model on second load', () async {
      final harness = createHarness(
        clientFactory: ({required libraryPath}) => fakeClient,
      );

      // Load first time.
      harness.handleMessage(
        const LoadModelRequest(
          modelPath: '/models/test.gguf',
          libraryPath: '/lib/libllama.so',
        ).toJson(),
      );

      // Wait for progress + loaded.
      await collectResponses(2);

      final firstPointer = fakeClient.lastHandles!.model.address;
      final loadCount = fakeClient.loadModelCalls;

      // Load second time - should be cached.
      harness.handleMessage(
        const LoadModelRequest(
          modelPath: '/models/test.gguf',
          libraryPath: '/lib/libllama.so',
        ).toJson(),
      );

      final response = await expectResponse();
      expect(fakeClient.loadModelCalls, loadCount); // No new load call.

      final loaded = response as ModelLoadedResponse;
      expect(loaded.modelPointer, firstPointer);
    });

    test('unload_model decrements ref count and frees on zero', () async {
      final harness = createHarness(
        clientFactory: ({required libraryPath}) => fakeClient,
      );

      // Load twice to get ref count of 2.
      harness.handleMessage(
        const LoadModelRequest(
          modelPath: '/models/test.gguf',
          libraryPath: '/lib/libllama.so',
        ).toJson(),
      );
      await collectResponses(2); // progress + loaded

      harness.handleMessage(
        const LoadModelRequest(
          modelPath: '/models/test.gguf',
          libraryPath: '/lib/libllama.so',
        ).toJson(),
      );
      await expectResponse(); // cached loaded

      // Unload once - ref count should be 1.
      harness.handleMessage(
        const UnloadModelRequest(modelPath: '/models/test.gguf').toJson(),
      );
      await expectResponse();

      expect(fakeClient.disposeCalls, 0);

      // Unload again - ref count should be 0 and model freed.
      harness.handleMessage(
        const UnloadModelRequest(modelPath: '/models/test.gguf').toJson(),
      );
      await expectResponse();

      expect(fakeClient.disposeCalls, 1);
    });

    test('unload_model for unknown model sends error', () async {
      final harness = createHarness(
        clientFactory: ({required libraryPath}) => fakeClient,
      );

      harness.handleMessage(
        const UnloadModelRequest(modelPath: '/models/unknown.gguf').toJson(),
      );

      final response = await expectResponse();
      expect(response, isA<ModelServerError>());
      expect(
        (response as ModelServerError).error,
        contains('Model not loaded'),
      );
    });

    test('dispose frees all loaded models and backend', () async {
      final harness = createHarness(
        clientFactory: ({required libraryPath}) => fakeClient,
      );

      // Load two models.
      harness.handleMessage(
        const LoadModelRequest(
          modelPath: '/models/a.gguf',
          libraryPath: '/lib/libllama.so',
        ).toJson(),
      );
      await collectResponses(2);

      harness.handleMessage(
        const LoadModelRequest(
          modelPath: '/models/b.gguf',
          libraryPath: '/lib/libllama.so',
        ).toJson(),
      );
      await collectResponses(2);

      expect(fakeClient.disposeCalls, 0);

      // Dispose server.
      harness.handleMessage(const DisposeModelServerRequest().toJson());

      // Give a moment for synchronous cleanup.
      await Future<void>.delayed(Duration.zero);

      expect(fakeClient.disposeCalls, 2);
      expect(bindings.backendFreeCalls, 1);
    });

    test('invalid message type sends error', () async {
      final harness = createHarness(
        clientFactory: ({required libraryPath}) => fakeClient,
      );

      // Send a malformed message.
      harness.handleMessage({'type': 'invalid_type'});

      final response = await expectResponse();
      expect(response, isA<ModelServerError>());
    });

    test('uses modelServerClientFactoryOverride when set', () async {
      var overrideCalled = false;
      modelServerClientFactoryOverride = ({required libraryPath}) {
        overrideCalled = true;
        return fakeClient;
      };

      final harness = createHarness();

      harness.handleMessage(
        const LoadModelRequest(
          modelPath: '/models/test.gguf',
          libraryPath: '/lib/libllama.so',
        ).toJson(),
      );

      await collectResponses(2);

      expect(overrideCalled, isTrue);
    });

    test('ignores non-map messages', () async {
      final harness = createHarness(
        clientFactory: ({required libraryPath}) => fakeClient,
      );

      // These should be silently ignored.
      harness.handleMessage('not a map');
      harness.handleMessage(42);
      harness.handleMessage(null);

      // Send a valid message to verify harness still works.
      harness.handleMessage(
        const LoadModelRequest(
          modelPath: '/models/test.gguf',
          libraryPath: '/lib/libllama.so',
        ).toJson(),
      );

      final responses = await collectResponses(2);
      expect(responses.whereType<ModelLoadedResponse>(), hasLength(1));
    });
  });

  group('modelServerIsolateEntry', () {
    test('sends receive port and handles messages', () async {
      final receivePort = ReceivePort();
      final sendPortCompleter = Completer<SendPort>();
      final responses = <Map<String, Object?>>[];

      receivePort.listen((message) {
        if (message is SendPort && !sendPortCompleter.isCompleted) {
          sendPortCompleter.complete(message);
        } else if (message is Map) {
          responses.add(Map<String, Object?>.from(message));
        }
      });

      // Spawn the isolate.
      final isolate = await Isolate.spawn(
        modelServerIsolateEntry,
        receivePort.sendPort,
      );

      final sendPort = await sendPortCompleter.future;
      expect(sendPort, isA<SendPort>());

      // Send a non-map message (should be ignored).
      sendPort.send('not a map');

      // Give time for message to be processed.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The isolate should still be running (didn't crash).
      expect(responses, isEmpty);

      isolate.kill();
      receivePort.close();
    });
  });
}

/// Fake LlamaClient for testing.
class _FakeLlamaClient implements LlamaClientApi {
  _FakeLlamaClient(this.bindings);

  final FakeLlamaBindings bindings;
  int loadModelCalls = 0;
  int disposeCalls = 0;
  LlamaHandles? lastHandles;

  int _modelPointerCounter = 1000;

  @override
  LlamaHandles loadModel({
    required String modelPath,
    required LlamaModelOptions modelOptions,
    ModelLoadProgressCallback? onProgress,
  }) {
    loadModelCalls++;

    // Always send a progress callback.
    onProgress?.call(0.5);

    final model = Pointer<llama_model>.fromAddress(_modelPointerCounter++);
    lastHandles = LlamaHandles(
      bindings: bindings,
      model: model,
      context: nullptr,
      vocab: Pointer.fromAddress(12),
    );
    return lastHandles!;
  }

  @override
  void dispose(LlamaHandles handles) {
    disposeCalls++;
  }

  @override
  Pointer<llama_context> createContext(
    LlamaHandles handles,
    LlamaContextOptions options,
  ) => throw UnimplementedError();

  @override
  void decode(
    LlamaHandles handles,
    Pointer<llama_context> context,
    List<int> tokens,
  ) => throw UnimplementedError();

  @override
  void resetContext(LlamaHandles handles, LlamaContextOptions options) =>
      throw UnimplementedError();

  @override
  int sampleNext(LlamaHandles handles, LlamaSamplerChain sampler) =>
      throw UnimplementedError();

  @override
  Uint8List tokenToBytes(
    LlamaHandles handles,
    int token, {
    int bufferSize = 32,
  }) => throw UnimplementedError();

  @override
  List<int> tokenize(
    LlamaHandles handles,
    String text, {
    bool addSpecial = true,
    bool parseSpecial = true,
  }) => throw UnimplementedError();
}
