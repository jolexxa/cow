import 'package:cow_brain/src/adapters/llama/llama.dart';
import 'package:test/test.dart';

import '../../../fixtures/fake_bindings.dart';

void main() {
  group('LlamaBackend', () {
    late FakeLlamaBindings bindings;

    setUp(() {
      bindings = FakeLlamaBindings();
      LlamaClient.openBindings = ({required String libraryPath}) => bindings;
    });

    tearDown(() {
      LlamaClient.openBindings = LlamaBindingsLoader.open;
    });

    test('ref-counts backend init/free across instances', () {
      final backendA = LlamaBackend(libraryPath: '/tmp/a');
      final backendB = LlamaBackend(libraryPath: '/tmp/a');

      backendA.ensureInitialized();
      expect(bindings.backendInitCalls, 1);

      backendB.ensureInitialized();
      expect(bindings.backendInitCalls, 1);

      backendA.release();
      expect(bindings.backendFreeCalls, 0);

      backendB.release();
      expect(bindings.backendFreeCalls, 1);
    });

    test('ensureInitialized validates when called twice on same instance', () {
      LlamaBackend(libraryPath: '/tmp/a')
        ..ensureInitialized()
        ..ensureInitialized()
        ..release();
    });

    test('rejects mismatched backend configuration', () {
      final backendA = LlamaBackend(libraryPath: '/tmp/a');
      final backendB = LlamaBackend(libraryPath: '/tmp/b');

      backendA.ensureInitialized();
      expect(
        backendB.ensureInitialized,
        throwsStateError,
      );
      backendA.release();
    });
  });
}
