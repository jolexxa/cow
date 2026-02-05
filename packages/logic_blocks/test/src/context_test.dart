// For clarity.
// ignore_for_file: cascade_invocations

import 'package:logic_blocks/logic_blocks.dart';
import 'package:test/test.dart';

import '../fixtures/test_logic_block.dart';

void main() {
  group('_ContextAdapter (via detached StateLogic)', () {
    // A freshly constructed state has no context, so calling context methods
    // should throw.
    late StateA state;

    setUp(() {
      state = StateA();
    });

    test('input throws when context is null', () {
      expect(() => state.input(const CustomInput()), throwsException);
    });

    test('output throws when context is null', () {
      expect(() => state.output(const OutputA()), throwsException);
    });

    test('get throws when context is null', () {
      expect(() => state.get<String>(), throwsException);
    });

    test('addError throws when context is null', () {
      expect(() => state.addError('error'), throwsException);
    });
  });

  group('$FakeContext', () {
    late FakeContext ctx;

    setUp(() {
      ctx = FakeContext();
    });

    test('captures inputs', () {
      ctx.input(const CustomInput());
      expect(ctx.inputs, hasLength(1));
      expect(ctx.inputs.first, isA<CustomInput>());
    });

    test('captures outputs', () {
      ctx.output(const OutputA());
      expect(ctx.outputs, hasLength(1));
      expect(ctx.outputs.first, isA<OutputA>());
    });

    test('captures errors', () {
      final e = Exception('boom');
      ctx.addError(e);
      expect(ctx.errors, hasLength(1));
      expect(ctx.errors.first, e);
    });

    test('get delegates to internal blackboard', () {
      ctx.set<String>('hello');
      expect(ctx.get<String>(), 'hello');
    });

    test('reset clears everything', () {
      ctx
        ..input(const CustomInput())
        ..output(const OutputA())
        ..addError('err')
        ..set<String>('data');

      ctx.reset();

      expect(ctx.inputs, isEmpty);
      expect(ctx.outputs, isEmpty);
      expect(ctx.errors, isEmpty);
      // blackboard should be cleared too
      expect(() => ctx.get<String>(), throwsArgumentError);
    });

    test('operator== always returns true', () {
      final other = FakeContext();
      expect(ctx == other, isTrue);
      expect(ctx == Object(), isTrue);
    });

    test('hashCode does not throw', () {
      expect(() => ctx.hashCode, returnsNormally);
    });
  });
}
