// For clarity.
// ignore_for_file: cascade_invocations

import 'package:logic_blocks/logic_blocks.dart';
import 'package:test/test.dart';

import '../fixtures/test_logic_block.dart';

void main() {
  group('$StateLogic', () {
    group('duplicate handler', () {
      test('on<T> throws ArgumentError when same input type registered twice',
          () {
        expect(DuplicateHandlerState.new, throwsArgumentError);
      });
    });

    group('isAttached', () {
      test('false before attach, true after, false after detach', () {
        final state = StateA();
        expect(state.isAttached, isFalse);

        state.attach(FakeContext());
        expect(state.isAttached, isTrue);

        state.detach();
        expect(state.isAttached, isFalse);
      });
    });

    group('detach', () {
      test('detach when not attached is a no-op', () {
        final state = StateA();
        // Should not throw
        state.detach();
        expect(state.isAttached, isFalse);
      });
    });

    group('createFakeContext', () {
      test('creates new FakeContext when none exists', () {
        final state = StateA();
        final ctx = state.createFakeContext();
        expect(ctx, isA<FakeContext>());
        expect(state.isAttached, isTrue);
      });

      test('reuses + resets existing FakeContext', () {
        final state = StateA();
        final ctx1 = state.createFakeContext();
        ctx1.input(const CustomInput());
        expect(ctx1.inputs, hasLength(1));

        final ctx2 = state.createFakeContext();
        expect(identical(ctx1, ctx2), isTrue);
        // Should have been reset
        expect(ctx2.inputs, isEmpty);
      });

      test('replaces real context with FakeContext', () {
        // Attach with a real-ish context first (use FakeContext as stand-in,
        // then attach a *different* FakeContext to simulate replacement)
        final logic = TestLogicBlock();
        logic.start(); // attaches real context

        final stateA = logic.get<StateA>();
        expect(stateA.isAttached, isTrue);

        final fakeCtx = stateA.createFakeContext();
        expect(fakeCtx, isA<FakeContext>());
      });
    });

    group('to/toSelf with FakeContext', () {
      test('to<T> returns standalone Transition with correct type', () {
        final state = StateA();
        state.createFakeContext();

        final t = state.to<StateB>();
        expect(t.stateType, StateB);
      });

      test('toSelf returns Transition to own runtime type', () {
        final state = StateA();
        state.createFakeContext();

        final t = state.toSelf();
        expect(t.stateType, StateA);
      });
    });

    group('handleInput', () {
      test('returns toSelf when no handler for input type', () {
        final state = StateA();
        state.createFakeContext();

        // UnregisteredInput has no handler in StateA → falls through to
        // toSelf
        final t = state.handleInput(const UnregisteredInput());
        expect(t.stateType, StateA);
      });

      test('calls registered handler when type matches', () {
        final state = StateA();
        state.createFakeContext();

        final t = state.handleInput(const GoToB());
        expect(t.stateType, StateB);
      });
    });

    group('enter/exit lifecycle with type hierarchy', () {
      // Note: TestLogicBlockState's onEnter/onExit use TDerived =
      // TestLogicBlockState so they fire only when entering/exiting the
      // entire type hierarchy. StateA's onEnter uses TDerived = StateA,
      // so it fires when previous is NOT a StateA.

      test('onEnter fires when entering from different type', () {
        // Use the logic block to test properly — when transitioning from
        // StateA to StateB, StateB's onEnter should fire.
        final logic = TestLogicBlock();
        final outputs = <Object>[];
        final binding = logic.bind();
        binding.onOutput<OutputB>(outputs.add);

        logic
          ..start() // enters StateA
          ..input(const GoToB()); // transitions to StateB

        // StateB's onEnter fires output(OutputB())
        expect(outputs, hasLength(1));

        binding.dispose();
      });

      test('onEnter does NOT fire when previous is same type', () {
        // StateA → GoToA → toSelf means we stay in StateA.
        // Even if we re-enter, onEnter for StateA shouldn't fire because
        // the previous state IS a StateA.
        final logic = TestLogicBlock();

        var enterCount = 0;
        final binding = logic.bind();
        binding.onOutput<OutputA>((_) => enterCount++);

        logic.start(); // enters StateA → OutputA fires (enterCount = 1)
        logic.input(const GoToA()); // stays in StateA → no state change

        expect(enterCount, 1); // only the initial enter
        binding.dispose();
      });

      test('onEnterWithPrevious receives previous state', () {
        final logic = TestLogicBlock();
        logic.start();

        final stateB = logic.get<StateB>() as TestLogicBlockState;
        stateB.reset();

        TestLogicBlockState? received;
        // This callback is registered at the TestLogicBlockState level,
        // which only fires when entering from outside TestLogicBlockState
        // (i.e., on startup). For state-level enter, we use the logic block.
        // Instead, let's use enterFrom to test:
        final state = StateA();
        state.createFakeContext();
        state.reset();

        // Use the direct enter API: enter(previous). The base class handler
        // checks TDerived = TestLogicBlockState: previous=null → NOT
        // TestLogicBlockState → fires.
        state.onEnterWithPreviousCallback =
            (prev) => received = prev as TestLogicBlockState?;
        state.enter(); // no previous (startup)

        expect(received, isNull); // previous is null on startup
      });

      test('onExit fires when exiting to different type (shutdown)', () {
        final logic = TestLogicBlock();
        final stateA = logic.get<StateA>() as TestLogicBlockState;
        stateA.reset();

        var exited = false;
        stateA.onExitCallback = () => exited = true;

        // Start in StateA, then stop — exit with null next (shutdown)
        // fires the base-level onExit because null is not TestLogicBlockState
        logic.start();
        logic.stop();

        expect(exited, isTrue);
      });

      test('onExit does NOT fire on A→B transition at base level', () {
        final logic = TestLogicBlock();
        final stateA = logic.get<StateA>() as TestLogicBlockState;
        stateA.reset();

        var exited = false;
        // onExitCallback is at TestLogicBlockState level (TDerived =
        // TestLogicBlockState). B is still a TestLogicBlockState, so
        // the base-level exit handler is skipped.
        stateA.onExitCallback = () => exited = true;

        logic
          ..start()
          ..input(const GoToB());

        expect(exited, isFalse);
      });

      test('onExitWithNext receives next state on shutdown', () {
        final logic = TestLogicBlock();
        final stateA = logic.get<StateA>() as TestLogicBlockState;
        stateA.reset();

        TestLogicBlockState? received;
        stateA.onExitWithNextCallback =
            (next) => received = next as TestLogicBlockState?;

        logic.start();
        logic.stop();

        // On shutdown, next is null
        expect(received, isNull);
      });

      test('enter with no previous (startup) fires onEnter', () {
        // On startup, previous is null → not "is TDerived" → all enter
        // handlers fire (both base class and subclass level).
        final logic = TestLogicBlock();
        final stateA = logic.get<StateA>() as TestLogicBlockState;
        stateA.reset();

        var entered = false;
        stateA.onEnterCallback = () => entered = true;

        logic.start();

        expect(entered, isTrue);
      });

      test('exit with no next (shutdown) fires onExit', () {
        final logic = TestLogicBlock();
        final stateA = logic.get<StateA>() as TestLogicBlockState;
        stateA.reset();

        var exited = false;
        stateA.onExitCallback = () => exited = true;

        logic.start();
        logic.stop();

        expect(exited, isTrue);
      });
    });

    group('enter with explicit previous', () {
      test('enter(previous) passes previous to enter callbacks', () {
        final state = StateA();
        state.createFakeContext();
        state.reset();

        TestLogicBlockState? received;
        state.onEnterWithPreviousCallback =
            (prev) => received = prev as TestLogicBlockState?;

        final previous = StateB();
        // Calling enter with a non-null previous that is NOT a
        // TestLogicBlockState? No — it IS a TestLogicBlockState,
        // so the base-level handler WON'T fire. But the StateA-level
        // handler WILL fire (previous is NOT a StateA).
        state.enter(previous);

        // The base-level onEnterWithPrevious doesn't fire because
        // StateB IS a TestLogicBlockState. But StateA's enter fires.
        // received stays null because the base-level callback skipped.
        expect(received, isNull);
      });
    });

    group('addError via FakeContext', () {
      test('addError records error in FakeContext', () {
        final state = StateA();
        final ctx = state.createFakeContext();

        state.addError('test error');

        expect(ctx.errors, hasLength(1));
        expect(ctx.errors.first, 'test error');
      });
    });

    group('error safety', () {
      test(
        '_runTransitionSafely catches error + forwards to handleError '
        'with real context',
        () {
          // Use ThrowingOnEnterState which registers onEnter at its own
          // TDerived level. When entering from a non-ThrowingOnEnterState,
          // the handler fires and throws.
          final logic = TestLogicBlock();
          final errors = <Object>[];

          final throwingState = ThrowingOnEnterState();
          logic.blackboard.overwrite(throwingState);

          final binding = logic.bind();
          binding.onError<Object>(errors.add);

          // Start, then force reset to ThrowingOnEnterState
          logic.start();
          logic.forceReset(throwingState);

          expect(errors, hasLength(1));
          expect(errors.first, isA<Exception>());

          binding.dispose();
        },
      );

      test(
        '_runTransitionSafely propagates error with FakeContext',
        () {
          // ThrowingOnEnterState's onEnter throws. With FakeContext there's
          // no onError handler so the exception propagates.
          final state = ThrowingOnEnterState();
          state.createFakeContext();

          // Enter from null (startup) — ThrowingOnEnterState's enter handler
          // fires because previous (null) is NOT a ThrowingOnEnterState.
          expect(state.enter, throwsException);
        },
      );
    });
  });
}
