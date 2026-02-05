import 'dart:async';
import 'dart:isolate';

import 'package:cow_brain/src/model_server/model_server.dart';
import 'package:test/test.dart';

/// Mock isolate entry point that simulates the real server behavior
/// without loading any real libraries.
void _mockIsolateEntry(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  final state = _MockServerState(sendPort);

  receivePort.listen((message) {
    if (message is! Map) return;
    state.handleMessage(Map<String, Object?>.from(message));
  });
}

class _MockServerState {
  _MockServerState(this._sendPort);

  final SendPort _sendPort;
  final Map<String, int> _models = {};
  final Map<String, int> _refCounts = {};
  int _pointerCounter = 10000;

  void handleMessage(Map<String, Object?> json) {
    final type = json['type'] as String?;

    switch (type) {
      case 'load_model':
        _handleLoadModel(json);
      case 'unload_model':
        _handleUnloadModel(json);
      case 'dispose':
        _models.clear();
        _refCounts.clear();
    }
  }

  void _handleLoadModel(Map<String, Object?> json) {
    final modelPath = json['modelPath']! as String;

    // Check for error mode.
    if (modelPath.contains('error')) {
      _sendPort.send({
        'type': 'error',
        'error': 'Simulated load error',
      });
      return;
    }

    // Check if already loaded.
    final existing = _models[modelPath];
    if (existing != null) {
      _refCounts[modelPath] = (_refCounts[modelPath] ?? 1) + 1;
      _sendPort.send({
        'type': 'model_loaded',
        'modelPath': modelPath,
        'modelPointer': existing,
      });
      return;
    }

    // Send progress.
    _sendPort.send({
      'type': 'load_progress',
      'modelPath': modelPath,
      'progress': 0.5,
    });

    // Load new model.
    final pointer = _pointerCounter++;
    _models[modelPath] = pointer;
    _refCounts[modelPath] = 1;

    _sendPort.send({
      'type': 'model_loaded',
      'modelPath': modelPath,
      'modelPointer': pointer,
    });
  }

  void _handleUnloadModel(Map<String, Object?> json) {
    final modelPath = json['modelPath']! as String;

    final refCount = _refCounts[modelPath];
    if (refCount == null) {
      _sendPort.send({
        'type': 'error',
        'error': 'Model not loaded: $modelPath',
      });
      return;
    }

    _refCounts[modelPath] = refCount - 1;
    if (_refCounts[modelPath]! <= 0) {
      _models.remove(modelPath);
      _refCounts.remove(modelPath);
    }

    _sendPort.send({
      'type': 'model_unloaded',
      'modelPath': modelPath,
    });
  }
}

void main() {
  group('ModelServer', () {
    setUp(() {
      modelServerIsolateEntryOverride = _mockIsolateEntry;
    });

    tearDown(() {
      modelServerIsolateEntryOverride = null;
    });

    test('spawn creates a server', () async {
      final server = await ModelServer.spawn();
      expect(server, isNotNull);
      await server.dispose();
    });

    test('loadModel returns LoadedModel', () async {
      final server = await ModelServer.spawn();

      final model = await server.loadModel(
        modelPath: '/models/test.gguf',
        libraryPath: '/lib/libllama.so',
      );

      expect(model.modelPath, '/models/test.gguf');
      expect(model.modelPointer, isPositive);

      await server.dispose();
    });

    test('loadModel returns cached model on second call', () async {
      final server = await ModelServer.spawn();

      final first = await server.loadModel(
        modelPath: '/models/test.gguf',
        libraryPath: '/lib/libllama.so',
      );

      final second = await server.loadModel(
        modelPath: '/models/test.gguf',
        libraryPath: '/lib/libllama.so',
      );

      expect(identical(first, second), isTrue);

      await server.dispose();
    });

    test('loadModel queues concurrent loads for same model', () async {
      final server = await ModelServer.spawn();

      final future1 = server.loadModel(
        modelPath: '/models/test.gguf',
        libraryPath: '/lib/libllama.so',
      );

      final future2 = server.loadModel(
        modelPath: '/models/test.gguf',
        libraryPath: '/lib/libllama.so',
      );

      final results = await Future.wait([future1, future2]);

      // Both should resolve to the same model.
      expect(identical(results[0], results[1]), isTrue);

      await server.dispose();
    });

    test('loadModel receives progress callbacks', () async {
      final server = await ModelServer.spawn();
      final progressValues = <double>[];

      await server.loadModel(
        modelPath: '/models/test.gguf',
        libraryPath: '/lib/libllama.so',
        onProgress: (progress) {
          progressValues.add(progress);
          return true;
        },
      );

      expect(progressValues, contains(0.5));

      await server.dispose();
    });

    test('unloadModel does not throw', () async {
      final server = await ModelServer.spawn();

      await server.loadModel(
        modelPath: '/models/test.gguf',
        libraryPath: '/lib/libllama.so',
      );

      // Should not throw.
      server.unloadModel('/models/test.gguf');

      await server.dispose();
    });

    test('LoadedModel.dispose does not throw', () async {
      final server = await ModelServer.spawn();

      final model = await server.loadModel(
        modelPath: '/models/test.gguf',
        libraryPath: '/lib/libllama.so',
      );

      // Should not throw.
      model.dispose();

      await server.dispose();
    });

    test('dispose is idempotent', () async {
      final server = await ModelServer.spawn();

      await server.dispose();
      await server.dispose(); // Should not throw.
    });

    test('operations after dispose throw StateError', () async {
      final server = await ModelServer.spawn();
      await server.dispose();

      expect(
        () => server.loadModel(
          modelPath: '/models/test.gguf',
          libraryPath: '/lib/libllama.so',
        ),
        throwsStateError,
      );

      expect(
        () => server.unloadModel('/models/test.gguf'),
        throwsStateError,
      );
    });

    test('loading different models returns different handles', () async {
      final server = await ModelServer.spawn();

      final modelA = await server.loadModel(
        modelPath: '/models/a.gguf',
        libraryPath: '/lib/libllama.so',
      );

      final modelB = await server.loadModel(
        modelPath: '/models/b.gguf',
        libraryPath: '/lib/libllama.so',
      );

      expect(modelA.modelPath, '/models/a.gguf');
      expect(modelB.modelPath, '/models/b.gguf');
      expect(modelA.modelPointer, isNot(equals(modelB.modelPointer)));

      await server.dispose();
    });

    test('unloadModel removes model from cache', () async {
      final server = await ModelServer.spawn();

      final first = await server.loadModel(
        modelPath: '/models/test.gguf',
        libraryPath: '/lib/libllama.so',
      );

      // Unload and wait for response to be processed.
      server.unloadModel('/models/test.gguf');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Loading again should return a new model (not cached).
      final second = await server.loadModel(
        modelPath: '/models/test.gguf',
        libraryPath: '/lib/libllama.so',
      );

      // Pointers should be different since model was unloaded.
      expect(second.modelPointer, isNot(equals(first.modelPointer)));

      await server.dispose();
    });

    test('error response completes pending loads with error', () async {
      final server = await ModelServer.spawn();

      // Model path containing 'error' triggers error response from mock.
      await expectLater(
        server.loadModel(
          modelPath: '/models/error.gguf',
          libraryPath: '/lib/libllama.so',
        ),
        throwsA(isA<StateError>()),
      );

      await server.dispose();
    });

    test(
      'error response completes multiple pending loads with error',
      () async {
        final server = await ModelServer.spawn();

        // Start two concurrent loads that will both fail.
        final future1 = server.loadModel(
          modelPath: '/models/error.gguf',
          libraryPath: '/lib/libllama.so',
        );
        final future2 = server.loadModel(
          modelPath: '/models/error.gguf',
          libraryPath: '/lib/libllama.so',
        );

        await expectLater(future1, throwsA(isA<StateError>()));
        await expectLater(future2, throwsA(isA<StateError>()));

        await server.dispose();
      },
    );
  });
}
