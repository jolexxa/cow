import 'package:cow_brain/src/adapters/mlx/mlx_handles.dart';
import 'package:test/test.dart';

import '../../../fixtures/fake_mlx_bindings.dart';

void main() {
  group('MlxHandles', () {
    late FakeMlxBindings bindings;

    setUp(() {
      bindings = FakeMlxBindings();
    });

    test('constructor stores fields correctly', () {
      final handles = MlxHandles(
        bindings: bindings,
        modelHandle: 5,
        contextHandle: 10,
      );

      expect(handles.bindings, same(bindings));
      expect(handles.modelHandle, 5);
      expect(handles.contextHandle, 10);
    });

    test(
      'fromModelId calls bindings.modelFromId and sets contextHandle to -1',
      () {
        bindings.modelFromIdResult = 7;

        final handles = MlxHandles.fromModelId(
          modelId: 42,
          bindings: bindings,
        );

        expect(bindings.modelFromIdCalls, 1);
        expect(handles.modelHandle, 7);
        expect(handles.contextHandle, -1);
        expect(handles.bindings, same(bindings));
      },
    );

    test('fromModelId throws StateError when modelFromId returns negative', () {
      bindings.modelFromIdResult = -1;

      expect(
        () => MlxHandles.fromModelId(modelId: 99, bindings: bindings),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('99'),
          ),
        ),
      );
    });

    test('modelId getter delegates to bindings.modelGetId', () {
      bindings.modelGetIdResult = 123;

      final handles = MlxHandles(
        bindings: bindings,
        modelHandle: 3,
        contextHandle: -1,
      );

      expect(handles.modelId, 123);
      expect(bindings.modelGetIdCalls, 1);
    });
  });
}
