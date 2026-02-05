part of 'logic_block.dart';

/// Callback invoked when an input of type [TInput] is received.
typedef InputCallback<TInput> = void Function(TInput input);

/// Callback invoked when a state of type [TState] is encountered.
typedef StateCallback<TState> = void Function(
  TState state,
);

/// Callback invoked when an output of type [TOutput] is produced.
typedef OutputCallback<TOutput> = void Function(TOutput output);

/// Callback invoked when an error of type [TError] is encountered.
typedef ErrorCallback<TError> = void Function(TError error);

typedef _Checker<T> = bool Function(T state);
typedef _Runner<T> = void Function(T state);

/// A binding to a logic block.
///
/// Bindings allow you to register callbacks for specific input types, state
/// types, output types, and error types. Using bindings enables more
/// declarative code and prevents unnecessary updates when a state has changed
/// but the relevant data within it has not.
///
/// Always [dispose] your binding when you are finished with it.
abstract interface class LogicBlockBinding<TState extends StateLogic<TState>>
    implements LogicBlockListener<TState> {
  /// Registers a [handler] to be invoked whenever an input of type [TInput]
  /// is received.
  void onInput<TInput extends Object>(InputCallback<TInput> handler);

  /// Registers a [handler] to be invoked whenever a state of type
  /// [TStateType] is encountered.
  void onState<TStateType extends TState>(StateCallback<TState> handler);

  /// Registers a [handler] to be invoked whenever an output of type [TOutput]
  /// is produced.
  void onOutput<TOutput extends Object>(OutputCallback<TOutput> handler);

  /// Registers a [handler] to be invoked whenever an error of type [TError]
  /// is encountered.
  void onError<TError>(ErrorCallback<TError> handler);
}

abstract base class _LogicBlockBindingBase<TState extends StateLogic<TState>>
    extends LogicBlockListener<TState> implements LogicBlockBinding<TState> {
  /// Map of an input type to a list of functions that receive that input.
  /// We store the functions non-generically and cast to the specific function
  /// type later when we have a generic argument available.
  final List<_Checker<Object>> _inputCheckers = [];
  final List<_Runner<Object>> _inputRunners = [];
  final List<_Checker<Object>> _outputCheckers = [];
  final List<_Runner<Object>> _outputRunners = [];

  /// List of functions that receive a TState and return whether the binding
  /// with the same index in the _whenBindingRunners should be run.
  final List<_Checker<TState>> _stateCheckers = [];

  /// List of functions that receive a TState and invoke the relevant binding
  /// when a particular type of state is encountered.
  final List<_Runner<TState>> _stateRunners = [];

  /// List of functions that receive an Exception and return whether the
  /// binding with the same index in the _errorRunners should be run.
  final List<_Checker<Object>> _exceptionCheckers = [];

  /// List of functions that receive an Exception and invoke the relevant
  /// binding when a particular type of error is encountered.
  final List<_Runner<Object>> _exceptionRunners = [];

  @override
  void onInput<TInput extends Object>(InputCallback<TInput> handler) {
    _inputCheckers.add((input) => input is TInput);
    _inputRunners.add((input) => handler(input as TInput));
  }

  @override
  void onState<TStateType extends TState>(
    StateCallback<TStateType> handler,
  ) {
    _stateCheckers.add((state) => state is TStateType);
    _stateRunners.add((state) => handler(state as TStateType));
  }

  @override
  void onOutput<TOutput extends Object>(OutputCallback<TOutput> handler) {
    _outputCheckers.add((output) => output is TOutput);
    _outputRunners.add((output) => handler(output as TOutput));
  }

  @override
  void onError<TError>(ErrorCallback<TError> handler) {
    _exceptionCheckers.add((error) => error is TError);
    _exceptionRunners.add((error) => handler(error as TError));
  }

  @override
  void cleanup() {
    _inputRunners.clear();
    _outputRunners.clear();
    _stateCheckers.clear();
    _stateRunners.clear();
    _exceptionCheckers.clear();
    _exceptionRunners.clear();

    super.cleanup();
  }

  @override
  void receiveInput<TInput extends Object>(TInput input) {
    for (var i = 0; i < _inputCheckers.length; i++) {
      if (_inputCheckers[i](input)) {
        _inputRunners[i](input);
      }
    }
  }

  @override
  void receiveState(TState state) {
    for (var i = 0; i < _stateCheckers.length; i++) {
      if (_stateCheckers[i](state)) {
        _stateRunners[i](state);
      }
    }
  }

  @override
  void receiveOutput<TOutput extends Object>(TOutput output) {
    for (var i = 0; i < _outputCheckers.length; i++) {
      if (_outputCheckers[i](output)) {
        _outputRunners[i](output);
      }
    }
  }

  @override
  void receiveError(Object error) {
    for (var i = 0; i < _exceptionCheckers.length; i++) {
      if (_exceptionCheckers[i](error)) {
        _exceptionRunners[i](error);
      }
    }
  }
}

final class _LogicBlockBinding<TState extends StateLogic<TState>>
    extends _LogicBlockBindingBase<TState> {
  _LogicBlockBinding(this.logicBlock) {
    logicBlock._addListener(this);
  }

  final LogicBlock<TState> logicBlock;

  @override
  void cleanup() {
    logicBlock._removeListener(this);

    super.cleanup();
  }
}
