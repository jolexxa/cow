// For clarity.
// ignore_for_file: cascade_invocations

import 'dart:async';

import 'package:logic_blocks/logic_blocks.dart';
import 'package:test/test.dart';

import '../fixtures/test_logic_block.dart';

void main() {
  group('$StatefulFuture', () {
    late AsyncLogicBlock logic;

    setUp(() {
      logic = AsyncLogicBlock();
      logic.start();
    });

    test('input delivers input on success', () async {
      final completer = Completer<String>();
      final inputs = <Object>[];
      final binding = logic.bind();
      binding.onInput<AsyncSuccessInput>(inputs.add);

      final state = logic.get<AsyncState>();
      state.async(completer.future).input(AsyncSuccessInput.new);

      completer.complete('hello');
      await Future<void>.delayed(Duration.zero);

      expect(inputs, hasLength(1));
      expect((inputs.first as AsyncSuccessInput).data, 'hello');

      binding.dispose();
    });

    test('errorInput delivers input on error', () async {
      final completer = Completer<String>();
      final inputs = <Object>[];
      final binding = logic.bind();
      binding.onInput<AsyncErrorInput>(inputs.add);

      final state = logic.get<AsyncState>();
      state.async(completer.future).errorInput(AsyncErrorInput.new);

      completer.completeError(Exception('boom'));
      await Future<void>.delayed(Duration.zero);

      expect(inputs, hasLength(1));
      expect((inputs.first as AsyncErrorInput).error, isA<Exception>());

      binding.dispose();
    });

    test('chaining only fires matching handler on success', () async {
      final completer = Completer<String>();
      final inputs = <Object>[];
      var errorFired = false;
      final binding = logic.bind();
      binding
        ..onInput<AsyncSuccessInput>(inputs.add)
        ..onInput<AsyncErrorInput>((_) => errorFired = true);

      final state = logic.get<AsyncState>();
      state
          .async(completer.future)
          .input(AsyncSuccessInput.new)
          .errorInput(AsyncErrorInput.new);

      completer.complete('ok');
      await Future<void>.delayed(Duration.zero);

      expect(inputs, hasLength(1));
      expect(errorFired, isFalse);

      binding.dispose();
    });

    test('chaining only fires matching handler on error', () async {
      final completer = Completer<String>();
      final inputs = <Object>[];
      var successFired = false;
      final binding = logic.bind();
      binding
        ..onInput<AsyncSuccessInput>((_) => successFired = true)
        ..onInput<AsyncErrorInput>(inputs.add);

      final state = logic.get<AsyncState>();
      state
          .async(completer.future)
          .input(AsyncSuccessInput.new)
          .errorInput(AsyncErrorInput.new);

      completer.completeError(Exception('fail'));
      await Future<void>.delayed(Duration.zero);

      expect(inputs, hasLength(1));
      expect(successFired, isFalse);

      binding.dispose();
    });

    test('no success handler does not crash', () async {
      final completer = Completer<String>();

      final state = logic.get<AsyncState>();
      state.async(completer.future); // no .input() chained

      completer.complete('ok');
      await Future<void>.delayed(Duration.zero);

      // Should not throw — just silently does nothing.
    });

    test('no error handler does not crash', () async {
      final completer = Completer<String>();

      final state = logic.get<AsyncState>();
      state.async(completer.future); // no .errorInput() chained

      completer.completeError(Exception('fail'));
      await Future<void>.delayed(Duration.zero);

      // Should not throw — just silently does nothing.
    });

    test('input is silently dropped after stop', () async {
      final completer = Completer<String>();
      final inputs = <Object>[];
      final binding = logic.bind();
      binding.onInput<AsyncSuccessInput>(inputs.add);

      final state = logic.get<AsyncState>();
      state.async(completer.future).input(AsyncSuccessInput.new);

      logic.stop();

      completer.complete('too late');
      await Future<void>.delayed(Duration.zero);

      expect(inputs, isEmpty);

      binding.dispose();
    });

    test('input is silently dropped after dispose', () async {
      final completer = Completer<String>();
      final inputs = <Object>[];
      final binding = logic.bind();
      binding.onInput<AsyncSuccessInput>(inputs.add);

      final state = logic.get<AsyncState>();
      state.async(completer.future).input(AsyncSuccessInput.new);

      logic.dispose();

      completer.complete('too late');
      await Future<void>.delayed(Duration.zero);

      expect(inputs, isEmpty);

      binding.dispose();
    });

    test('input survives state transition', () async {
      final completer = Completer<String>();
      final inputs = <Object>[];
      final binding = logic.bind();
      binding.onInput<AsyncSuccessInput>(inputs.add);

      // Start async from AsyncState, then transition to StateB
      final state = logic.get<AsyncState>();
      state.async(completer.future).input(AsyncSuccessInput.new);

      logic.input(const GoToB());
      expect(logic.value, isA<StateB>());

      // Future completes after state change — input should still arrive
      completer.complete('arrived');
      await Future<void>.delayed(Duration.zero);

      expect(inputs, hasLength(1));
      expect((inputs.first as AsyncSuccessInput).data, 'arrived');

      binding.dispose();
    });

    test('works with FakeContext', () async {
      final state = AsyncState();
      final ctx = state.createFakeContext();

      final completer = Completer<String>();
      state.async(completer.future).input(AsyncSuccessInput.new);

      completer.complete('fake');
      await Future<void>.delayed(Duration.zero);

      expect(ctx.inputs, hasLength(1));
      expect((ctx.inputs.first as AsyncSuccessInput).data, 'fake');
    });

    test('logic.task completes after async future resolves', () async {
      final completer = Completer<String>();

      final state = logic.get<AsyncState>();
      state.async(completer.future).input(AsyncSuccessInput.new);

      var taskDone = false;
      unawaited(logic.task.then((_) => taskDone = true));

      expect(taskDone, isFalse);

      completer.complete('done');
      await logic.task;

      expect(taskDone, isTrue);
    });

    test('logic.task waits for multiple async futures', () async {
      final c1 = Completer<String>();
      final c2 = Completer<String>();

      final state = logic.get<AsyncState>();
      state.async(c1.future).input(AsyncSuccessInput.new);
      state.async(c2.future).input(AsyncSuccessInput.new);

      var taskDone = false;
      unawaited(logic.task.then((_) => taskDone = true));

      c1.complete('first');
      await Future<void>.delayed(Duration.zero);
      expect(taskDone, isFalse);

      c2.complete('second');
      await logic.task;
      expect(taskDone, isTrue);
    });

    test('FakeContext.task completes after async future resolves', () async {
      final state = AsyncState();
      final ctx = state.createFakeContext();

      final completer = Completer<String>();
      state.async(completer.future).input(AsyncSuccessInput.new);

      var taskDone = false;
      unawaited(ctx.task.then((_) => taskDone = true));

      expect(taskDone, isFalse);

      completer.complete('fake');
      await ctx.task;

      expect(taskDone, isTrue);
      expect(ctx.inputs, hasLength(1));
    });

    test('FakeContext with stopped status drops input', () async {
      final state = AsyncState();
      final ctx = state.createFakeContext();
      ctx.status = LogicBlockStatus.stopped;

      final completer = Completer<String>();
      state.async(completer.future).input(AsyncSuccessInput.new);

      completer.complete('dropped');
      await Future<void>.delayed(Duration.zero);

      expect(ctx.inputs, isEmpty);
    });
  });
}
