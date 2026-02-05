// Test models.
// ignore_for_file: hash_and_equals

import 'package:collections/collections.dart';
import 'package:equatable/equatable.dart';
import 'package:logic_blocks/logic_blocks.dart';

sealed class TestInput {
  const TestInput();
}

final class CustomInput extends TestInput {
  const CustomInput();
}

final class GoToA extends TestInput {
  const GoToA();
}

final class GoToB extends TestInput {
  const GoToB();
}

final class AddError extends TestInput {
  const AddError(this.e);

  final Object e;
}

abstract base class TestLogicBlockState
    extends StateLogic<TestLogicBlockState> {
  TestLogicBlockState() {
    onEnter(() => onEnterCallback?.call());
    onExit(() => onExitCallback?.call());
    onEnterWithPrevious((prev) => onEnterWithPreviousCallback?.call(prev));
    onExitWithNext((next) => onExitWithNextCallback?.call(next));
    on<CustomInput>((input) {
      output(CustomInputReceived(input));
      return onInputCallback?.call(this, input) ?? toSelf();
    });
    on<AddError>((input) {
      addError(input.e);
      return toSelf();
    });
  }

  // customizable callbacks for testing logic block behavior
  VoidCallback? onEnterCallback;
  VoidCallback? onExitCallback;
  ValueCallback<dynamic>? onEnterWithPreviousCallback;
  ValueCallback<dynamic>? onExitWithNextCallback;
  Func2Callback<TestLogicBlockState, TestInput, Transition>? onInputCallback;

  // expose protected members for testing
  @override
  void on<TInput>(Func1Callback<TInput, Transition> handler) =>
      super.on<TInput>(handler);

  @override
  TData get<TData extends Object>() => super.get<TData>();

  @override
  void addError(Object e) => super.addError(e);

  @override
  void input<TInput extends Object>(TInput input) => super.input<TInput>(input);

  @override
  void output<TOutput extends Object>(TOutput output) =>
      super.output<TOutput>(output);

  @override
  Transition to<TNextState extends TestLogicBlockState>() =>
      super.to<TNextState>();

  @override
  Transition toSelf() => super.toSelf();

  void reset() {
    onEnterCallback = null;
    onExitCallback = null;
    onEnterWithPreviousCallback = null;
    onExitWithNextCallback = null;
    onInputCallback = null;
  }
}

final class StateA extends TestLogicBlockState {
  StateA() {
    onEnter(() => output(const OutputA()));

    on<GoToA>((input) => toSelf());
    on<GoToB>((input) => to<StateB>());
  }
}

final class StateB extends TestLogicBlockState {
  StateB() {
    onEnter(() => output(const OutputB()));

    on<GoToA>((input) => to<StateA>());
    on<GoToB>((input) => toSelf());
  }
}

final class TestLogicBlock extends LogicBlock<TestLogicBlockState> {
  TestLogicBlock({this.startInStateA = true}) {
    set(StateA());
    set(StateB());
  }

  final bool startInStateA;

  VoidCallback? onStartCallback;
  VoidCallback? onStopCallback;

  @override
  Transition getInitialState() => startInStateA ? to<StateA>() : to<StateB>();

  @override
  void onStart() => onStartCallback?.call();

  @override
  void onStop() => onStopCallback?.call();
}

sealed class TestOutput {
  const TestOutput();
}

final class OutputA extends TestOutput {
  const OutputA();
}

final class OutputB extends TestOutput {
  const OutputB();
}

final class CustomInputReceived extends TestOutput {
  const CustomInputReceived(this.input);

  final CustomInput input;
}

class TestModelA extends Equatable {
  const TestModelA({required this.value});

  final String value;

  @override
  List<Object?> get props => [value];
}

class TestModelB extends Equatable {
  const TestModelB({required this.value});

  final String value;

  @override
  List<Object?> get props => [value];
}

class TestModelC extends Equatable {
  const TestModelC({required this.value});

  final String value;

  @override
  List<Object?> get props => [value];
}

class TestModelFalse {
  @override
  bool operator ==(Object other) => false;
}

class TestModelTrue {
  @override
  bool operator ==(Object other) => true;
}

/// State that registers the same input handler twice (for testing throw).
final class DuplicateHandlerState extends TestLogicBlockState {
  DuplicateHandlerState() {
    // CustomInput is already registered in the parent constructor.
    // Registering it again should throw.
    on<CustomInput>((input) => toSelf());
  }
}

/// State with an onEnter that throws.
final class ThrowingOnEnterState extends TestLogicBlockState {
  ThrowingOnEnterState() {
    onEnter(() => throw Exception('onEnter threw'));
  }
}

/// State with no extra handlers beyond what TestLogicBlockState provides.
final class UnhandledInputState extends TestLogicBlockState {}

/// An input type no state registers a handler for.
final class UnregisteredInput {
  const UnregisteredInput();
}

/// State that calls get() during input handling.
final class GetDuringInputState extends TestLogicBlockState {
  GetDuringInputState() {
    on<GoToA>((input) {
      final model = get<TestModelA>();
      output(const CustomInputReceived(CustomInput()));
      return model.value == 'found' ? to<StateB>() : toSelf();
    });
    on<GoToB>((input) => to<StateB>());
  }
}

/// Logic block that uses GetDuringInputState to test context.get().
final class GetDuringInputLogicBlock extends LogicBlock<TestLogicBlockState> {
  GetDuringInputLogicBlock() {
    set(GetDuringInputState());
    set(StateB());
    set(const TestModelA(value: 'found'));
  }

  @override
  Transition getInitialState() => to<GetDuringInputState>();
}

/// A different LogicBlock subclass for operator== tests.
final class AltTestLogicBlock extends LogicBlock<TestLogicBlockState> {
  AltTestLogicBlock() {
    set(StateA());
    set(StateB());
  }

  @override
  Transition getInitialState() => to<StateA>();
}
