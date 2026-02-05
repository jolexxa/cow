// For clarity.
// ignore_for_file: cascade_invocations

import 'package:logic_blocks/logic_blocks.dart';
import 'package:test/test.dart';

import '../fixtures/test_logic_block.dart';

void main() {
  late TestLogicBlock logic;
  late TestLogicBlockState stateA;
  late TestLogicBlockState stateB;

  setUp(() {
    logic = TestLogicBlock();

    stateA = logic.get<StateA>()..reset();
    stateB = logic.get<StateB>()..reset();
  });

  group('LogicBlocks', () {
    test('can be instantiated', () {
      expect(TestLogicBlock(), isNotNull);
    });

    test('isEquivalent', () {
      const modelA = TestModelA(value: 'a');
      const modelA2 = TestModelA(value: 'a2');
      const modelB = TestModelB(value: 'b');
      final false1 = TestModelFalse();
      final false2 = TestModelFalse();
      final true1 = TestModelTrue();
      final true2 = TestModelTrue();

      // same reference
      expect(LogicBlock.isEquivalent(modelA, modelA), isTrue);
      // not equivalent, but same runtime type
      expect(LogicBlock.isEquivalent(modelA, modelA2), isTrue);
      // not equivalent
      expect(LogicBlock.isEquivalent(modelA, modelB), isFalse);
      // not equivalent, but same runtime type
      expect(LogicBlock.isEquivalent(false1, false2), isTrue);
      // equivalent (despite runtime type differences, since == should take
      // precedence over the runtime type check)
      expect(LogicBlock.isEquivalent(true1, true2), isTrue);
    });

    group('input handling', () {
      test('queues subsequent inputs', () {
        var numInputs = 0;

        stateA.onInputCallback = (state, input) {
          numInputs++;

          // add another input while handling the current one
          state.input(const CustomInput());

          if (numInputs > 1) {
            return state.to<StateB>();
          }

          return state.toSelf();
        };

        stateB.onInputCallback = (state, input) {
          numInputs++;
          return state.toSelf();
        };

        logic.input(const CustomInput());

        expect(logic.value, isA<StateB>());
        expect(numInputs, 3);
      });
    });

    group('start and stop', () {
      test('start enters initial state', () {
        expect(logic.valueAsObject, isNull);

        logic.start();

        expect(logic.valueAsObject, isA<StateA>());
      });

      test(
        'stop exits current state to null and '
        'discards any inputs added during exit',
        () {
          var numInputs = 0;
          var onExitCalled = false;

          stateA
            ..onInputCallback = (state, input) {
              numInputs++;
              return state.toSelf();
            }
            ..onExitCallback = () {
              logic.input(const CustomInput());
              onExitCalled = true;
            };

          logic.start();

          expect(logic.value, isA<StateA>());

          logic.stop();

          expect(logic.valueAsObject, isNull);
          expect(numInputs, 0);
          expect(onExitCalled, isTrue);
        },
      );
    });

    group('onStart and onStop', () {
      test('onStart is called when start() is invoked', () {
        var onStartCalled = false;
        logic.onStartCallback = () => onStartCalled = true;

        logic.start();

        expect(onStartCalled, isTrue);
      });

      test('onStart is called on first lazy access via value', () {
        var onStartCalled = false;
        logic.onStartCallback = () => onStartCalled = true;

        // Access value lazily (triggers _flush)
        final _ = logic.value;

        expect(onStartCalled, isTrue);
      });

      test('onStart is not called again on subsequent accesses', () {
        var onStartCount = 0;
        logic.onStartCallback = () => onStartCount++;

        logic.start();

        // Access value again
        final _ = logic.value;

        // Send an input
        logic.input(const CustomInput());

        expect(onStartCount, 1);
      });

      test('onStop is called when stop() is invoked', () {
        var onStopCalled = false;
        logic.onStopCallback = () => onStopCalled = true;

        logic.start();
        logic.stop();

        expect(onStopCalled, isTrue);
      });

      test('onStart and onStop fire again after stop + start cycle', () {
        var onStartCount = 0;
        var onStopCount = 0;
        logic.onStartCallback = () => onStartCount++;
        logic.onStopCallback = () => onStopCount++;

        logic.start();
        logic.stop();
        logic.start();
        logic.stop();

        expect(onStartCount, 2);
        expect(onStopCount, 2);
      });
    });

    group('forceReset', () {
      test('throws StateError when called while processing inputs', () {
        stateA.onInputCallback = (state, input) {
          // Try to force reset while processing
          expect(
            () => logic.forceReset(StateB()),
            throwsA(isA<StateError>()),
          );
          return state.toSelf();
        };

        logic.input(const CustomInput());
      });

      test('changes state when not processing', () {
        logic.start();
        expect(logic.value, isA<StateA>());

        logic.forceReset(logic.get<StateB>());
        expect(logic.value, isA<StateB>());
      });
    });

    group('restoreState', () {
      test('throws StateError when logic block is already running', () {
        logic.start();
        expect(
          () => logic.restoreState(StateA()),
          throwsA(isA<StateError>()),
        );
      });

      test('stores state for later restoration on start', () {
        final restoredState = StateB();
        logic.blackboard.overwrite(restoredState);
        logic.restoreState(restoredState);

        logic.start();
        expect(logic.value, isA<StateB>());
      });
    });

    group('restoreFrom', () {
      test('throws StateError when source has not started', () {
        final source = TestLogicBlock();
        expect(() => logic.restoreFrom(source), throwsA(isA<StateError>()));
      });

      test('copies blackboard + state from started source', () {
        final source = TestLogicBlock();
        source.start();
        source.blackboard.overwrite(const TestModelA(value: 'copied'));

        logic.restoreFrom(source);
        logic.start();

        expect(logic.value, isA<StateA>());
        expect(logic.get<TestModelA>().value, 'copied');
      });
    });

    group('operator==', () {
      test('identical references are equal', () {
        expect(logic == logic, isTrue);
      });

      test('non-LogicBlockBase is not equal', () {
        // Gotta test unrelated type equality checks too
        // ignore: unrelated_type_equality_checks
        expect(logic == 'not a logic block', isFalse);
      });

      test('different runtimeType is not equal', () {
        final alt = AltTestLogicBlock();
        logic.start();
        alt.start();
        expect(logic == alt, isFalse);
      });

      test('different state values are not equal', () {
        final other = TestLogicBlock();
        logic.start(); // in StateA
        other
          ..start()
          ..input(const GoToB()); // in StateB
        expect(logic == other, isFalse);
      });

      test('different blackboard types count is not equal', () {
        final other = TestLogicBlock();
        logic.start();
        other.start();

        logic.blackboard.overwrite(const TestModelA(value: 'x'));

        expect(logic == other, isFalse);
      });

      test('same types but different runtimeType values is not equal', () {
        final other = TestLogicBlock();
        logic.start();
        other.start();

        // Store different runtime types under the same blackboard key
        // by using overwriteObject with the same Type key but values of
        // different runtimeType
        logic.blackboard
            .overwriteObject(TestModelA, const TestModelA(value: 'a'));
        other.blackboard
            .overwriteObject(TestModelA, const TestModelB(value: 'b'));

        expect(logic == other, isFalse);
      });

      test('matching state + blackboard are equal', () {
        final other = TestLogicBlock();
        logic.start();
        other.start();

        expect(logic == other, isTrue);
      });
    });

    group('context.get<T>()', () {
      test('state can call get<T>() during input handling', () {
        final block = GetDuringInputLogicBlock();
        block.start();

        expect(block.value, isA<GetDuringInputState>());

        // GoToA handler in GetDuringInputState calls get<TestModelA>()
        block.input(const GoToA());
        expect(block.value, isA<StateB>());
      });
    });

    group('Transition double-call', () {
      test('double _transition() call throws via logic block', () {
        // When a state handler calls to<T>() inside a real logic block,
        // a double call on the shared Transition object should throw.
        // The error gets caught by the error handler.
        final errors = <Object>[];
        final binding = logic.bind();
        binding.onError<Object>(errors.add);

        stateA.onInputCallback = (state, input) {
          // First to<T> call — OK
          final transition = state.to<StateB>();
          // Second to<T> call on same shared Transition — throws
          try {
            state.to<StateA>();
          } on Object catch (e) {
            state.addError(e);
          }
          return transition;
        };

        logic.input(const CustomInput());

        expect(errors, hasLength(1));
        expect(errors.first.toString(), contains('do not call'));

        binding.dispose();
      });
    });

    group('isEquivalent edge cases', () {
      test('isEquivalent(null, null) returns true', () {
        expect(LogicBlock.isEquivalent(null, null), isTrue);
      });

      test('isEquivalent(null, non-null) returns false', () {
        expect(LogicBlock.isEquivalent(null, 'a'), isFalse);
      });

      test('isEquivalent(non-null, null) returns false', () {
        expect(LogicBlock.isEquivalent('a', null), isFalse);
      });
    });

    group('operator== edge cases', () {
      test('non-overlapping blackboard types are not equal', () {
        final other = TestLogicBlock();
        logic.start();
        other.start();

        logic.blackboard.overwrite(const TestModelA(value: 'x'));
        other.blackboard.overwrite(const TestModelC(value: 'y'));

        expect(logic == other, isFalse);
      });
    });

    group('restoreFrom edge cases', () {
      test('restores from source with restored-but-not-started state', () {
        final source = TestLogicBlock();
        final restoredState = StateB();
        source.blackboard.overwrite(restoredState);
        source.restoreState(restoredState);

        // Source has a _restoredState but no _value (never started)
        logic.restoreFrom(source);
        logic.start();

        expect(logic.value, isA<StateB>());
      });
    });

    group('edge cases', () {
      test('start() when already started is a no-op', () {
        logic.start();
        final state = logic.value;
        logic.start();
        expect(identical(logic.value, state), isTrue);
      });

      test('stop() when not started is a no-op', () {
        logic.stop();
        expect(logic.valueAsObject, isNull);
      });

      test('hashCode does not throw', () {
        logic.start();
        expect(() => logic.hashCode, returnsNormally);
      });

      test('base onStop() is a no-op by default', () {
        // AltTestLogicBlock does not override onStop()
        final alt = AltTestLogicBlock();
        alt.start();
        alt.stop(); // calls base LogicBlock.onStop() {}
        expect(alt.valueAsObject, isNull);
      });

      test('createFakeBinding returns LogicBlockFakeBinding', () {
        final binding = LogicBlock.createFakeBinding<TestLogicBlockState>();
        expect(binding, isA<LogicBlockFakeBinding<TestLogicBlockState>>());
      });
    });
  });
}
