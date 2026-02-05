import 'package:logic_blocks/logic_blocks.dart';
import 'package:test/test.dart';

import '../fixtures/test_logic_block.dart';

void main() {
  group('$LogicBlockBinding', () {
    late TestLogicBlock logic;
    late LogicBlockBinding<TestLogicBlockState> binding;

    setUp(() {
      logic = TestLogicBlock();
      binding = logic.bind();
    });

    tearDown(() {
      binding.dispose();
    });

    test('matching state runs again if not equivalent to previous', () {
      var called = 0;

      binding.onState<TestLogicBlockState>((state) => called++);
      logic
        ..input(const GoToB())
        ..input(const GoToA());

      // one binding invocation for initial state + 2 state changes
      expect(called, 3);
    });

    test('matching state does not run again if equivalent to previous', () {
      var called = 0;

      binding.onState<TestLogicBlockState>((state) => called++);

      logic.input(const GoToA()); // already in A, so nothing happens

      expect(called, 1);
    });

    test('handles outputs', () {
      var a = 0;
      var b = 0;

      binding
        ..onOutput<OutputA>((output) => a++)
        ..onOutput<OutputB>((output) => b++);

      // starting state (A) fires its output automatically once the logic block
      // is started (or receives its first input)
      logic
        ..start()
        ..input(const GoToB())
        ..input(const CustomInput()); // produces an output we don't listen to.

      expect(a, 1);
      expect(b, 1);
    });

    test('handles errors', () {
      final errors = <Object>[];

      binding.onError(errors.add);

      final e = Exception('Test error');

      logic.input(AddError(e));

      expect(errors.single, e);
    });

    test('handles inputs', () {
      final inputs = <Object>[];
      var b = 0;

      binding
        ..onInput(inputs.add)
        ..onInput<GoToB>((_) => b++);

      logic
        ..input(const CustomInput())
        ..input(const GoToB())
        ..input(const GoToA())
        ..input(const GoToB());

      expect(inputs[0], isA<CustomInput>());
      expect(inputs[1], isA<GoToB>());
      expect(inputs[2], isA<GoToA>());
      expect(inputs[3], isA<GoToB>());

      expect(b, 2);
    });

    test('dispose prevents handlers from firing', () {
      var called = false;
      binding
        ..onState<TestLogicBlockState>((_) => called = true)
        ..dispose();

      logic.input(const GoToB());

      expect(called, isFalse);
    });

    test('non-matching state type does NOT trigger handler', () {
      var called = false;
      binding.onState<StateB>((_) => called = true);

      // Start in StateA — should not match StateB handler
      logic.start();

      expect(called, isFalse);
    });

    test('non-matching input type does NOT trigger handler', () {
      var called = false;
      binding.onInput<GoToA>((_) => called = true);

      logic.input(const GoToB());

      expect(called, isFalse);
    });

    test('non-matching output type does NOT trigger handler', () {
      var called = false;
      binding.onOutput<OutputB>((_) => called = true);

      // Starting in StateA fires OutputA, not OutputB
      logic.start();

      expect(called, isFalse);
    });

    test('non-matching error type does NOT trigger handler', () {
      var called = false;
      binding.onError<FormatException>((_) => called = true);

      logic.input(AddError(Exception('not a format exception')));

      expect(called, isFalse);
    });

    test('multiple handlers of same type all fire', () {
      var count = 0;
      binding
        ..onState<TestLogicBlockState>((_) => count++)
        ..onState<TestLogicBlockState>((_) => count++);

      logic.start();

      expect(count, 2);
    });

    test('dispose is idempotent', () {
      binding
        ..dispose()
        // Second dispose should not throw
        ..dispose();
    });
  });
}
