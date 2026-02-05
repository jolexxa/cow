// For clarity.
// ignore_for_file: cascade_invocations

import 'package:logic_blocks/logic_blocks.dart';
import 'package:test/test.dart';

import '../fixtures/test_logic_block.dart';

void main() {
  group('$LogicBlockFakeBinding', () {
    late LogicBlockFakeBinding<TestLogicBlockState> binding;

    setUp(() {
      binding = LogicBlockFakeBinding<TestLogicBlockState>();
    });

    test('setState triggers onState handlers', () {
      final received = <TestLogicBlockState>[];
      binding.onState<TestLogicBlockState>(received.add);

      final state = StateA();
      binding.setState(state);

      expect(received.single, state);
    });

    test('input triggers onInput handlers', () {
      final received = <Object>[];
      binding.onInput<CustomInput>(received.add);

      binding.input(const CustomInput());

      expect(received.single, isA<CustomInput>());
    });

    test('output triggers onOutput handlers', () {
      final received = <Object>[];
      binding.onOutput<OutputA>(received.add);

      binding.output(const OutputA());

      expect(received.single, isA<OutputA>());
    });

    test('addError triggers onError handlers', () {
      final received = <Object>[];
      binding.onError(received.add);

      final e = Exception('test');
      binding.addError(e);

      expect(received.single, e);
    });

    test('after dispose, handlers do not fire', () {
      var called = false;
      binding.onState<TestLogicBlockState>((_) => called = true);

      binding.dispose();

      // After dispose, checkers/runners are cleared.
      binding.setState(StateA());

      expect(called, isFalse);
    });
  });
}
