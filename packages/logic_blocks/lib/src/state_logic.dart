part of 'logic_block.dart';

/// Base class for logic block states.
///
/// Inherit from this class to create a base state for a logic block. States
/// define input handlers, lifecycle callbacks, and transitions to other states.
///
/// States are attached to a logic block when they become the active state and
/// detached when replaced. Entrance and exit callbacks respect the state type
/// hierarchy.
abstract base class StateLogic<TState> {
  /// Creates a new state logic instance, initializing internal lifecycle
  /// handler storage.
  StateLogic() {
    _internalState = _InternalState<TState>(_ContextAdapter());
  }

  late final _InternalState<TState> _internalState;

  // Logic block states are reused singletons and state type hierarchy is
  // handled independent of equality mechanism. This prevents issues when used
  // with libraries which de-duplicate instances based on equality.
  @override
  bool operator ==(Object other) => false;

  @override
  int get hashCode => identityHashCode(this);

  /// Whether this state is currently attached to a logic block context.
  bool get isAttached => _internalState.isAttached;

  /// Register an input handler for inputs of type [TInput]. Input instances
  /// which have the same runtime type as [TInput] will be passed to [handler].
  /// Only one handler can be registered per input type — subsequent calls with
  /// the same input type will overwrite the previous handler.
  @protected
  void on<TInput>(Func1Callback<TInput, Transition> handler) =>
      _internalState.on<TInput>(handler);

  /// Gets a value of type [TData] from the logic block's blackboard.
  @protected
  TData get<TData extends Object>() => _internalState.get<TData>();

  /// Adds an error to the logic block. Errors are immediately processed by
  /// the logic block's [LogicBlock.handleError] callback.
  @protected
  void addError(Object e) => _internalState.addError(e);

  /// Adds an input value to the logic block's internal input queue.
  @protected
  void input<TInput extends Object>(TInput input) =>
      _internalState.input(input);

  /// Produces a logic block output value.
  @protected
  void output<TOutput extends Object>(TOutput output) =>
      _internalState.output(output);

  /// Runs all registered entrance callbacks for this state.
  ///
  /// [previous] is the state that was active before this one, if any.
  void enter([TState? previous]) =>
      _internalState.enter(this as TState, previous);

  /// Runs all registered exit callbacks for this state.
  ///
  /// [next] is the state that will become active after this one, if any.
  void exit([TState? next]) => _internalState.exit(this as TState, next);

  /// Attaches this state to the given [context].
  void attach(Context context) => _internalState.attach(context);

  /// Detaches this state from its context.
  void detach() => _internalState.detach();

  /// Defines a transition to the state of type [TNextState] stored on the
  /// blackboard.
  @protected
  Transition to<TNextState extends TState>() => _internalState.to<TNextState>();

  /// Defines a self-transition (re-enters the current state type).
  @protected
  Transition toSelf() => _internalState.toSelf(this as TState);

  /// Creates and attaches a [FakeContext] for unit testing this state in
  /// isolation. If a fake context is already attached, it is reset and
  /// returned.
  FakeContext createFakeContext() => _internalState.createFakeContext();

  /// Processes the given [input] through this state's registered input
  /// handlers and returns the resulting transition.
  Transition handleInput<TInput extends Object>(TInput input) =>
      _internalState.handleInput(this as TState, input);
}

enum _InternalStateOperation { enter, exit }

class _InternalState<TState>
    implements GenericListHandler<ObjCallbackNullable> {
  _InternalState(this.contextAdapter) {
    _enterHandlers = GenericList(handler: this);
    _exitHandlers = GenericList(handler: this);
  }

  final _ContextAdapter contextAdapter;

  late final GenericList<ObjCallbackNullable> _enterHandlers;
  late final GenericList<ObjCallbackNullable> _exitHandlers;
  final Map<Type, Func1Callback<Object, Transition>> _inputHandlers = {};
  _InternalStateOperation? _operation;
  TState? _previous;
  TState? _next;

  bool get isAttached => contextAdapter.isActive;

  void on<TInput>(Func1Callback<TInput, Transition> handler) {
    if (_inputHandlers.containsKey(TInput)) {
      throw ArgumentError(
        'An input handler for type $TInput has already been registered. '
            "If you are trying to customize a parent state's input handling, "
            'verify that the parent state passes a tearoff method to its '
            'on<TInput>(...) call and override that method in the child state.',
        'handler',
      );
    }
    _inputHandlers[TInput] = (input) => handler(input as TInput);
  }

  TData get<TData extends Object>() => contextAdapter.get<TData>();

  void addError(Object e) => contextAdapter.addError(e);

  void input<TInput extends Object>(TInput input) =>
      contextAdapter.input(input);

  void output<TOutput extends Object>(TOutput output) =>
      contextAdapter.output(output);

  void onEnter<TDerived>(ObjCallbackNullable handler) {
    _enterHandlers.add<TDerived>(handler);
  }

  void onExit<TDerived>(ObjCallbackNullable handler) {
    _exitHandlers.add<TDerived>(handler);
  }

  void enter(TState me, [TState? previous]) =>
      _callOnEnterHandlers(previous, me);

  void exit(TState me, [TState? next]) => _callOnExitHandlers(me, next);

  void attach(Context context) {
    contextAdapter.adapt(context);
  }

  void detach() {
    contextAdapter.deactivate();
  }

  FakeContext createFakeContext() {
    var context = contextAdapter.context;

    if (context is FakeContext) {
      context.reset();
      return context;
    }

    context = FakeContext();
    contextAdapter.adapt(context);

    return context;
  }

  Transition to<TNextState extends TState>() {
    final context = contextAdapter.context;

    if (context is _DefaultContext) {
      return context.logic._transition.._transition(TNextState);
    }

    return Transition._().._transition(TNextState);
  }

  Transition toSelf(TState me) {
    final context = contextAdapter.context;

    if (context is _DefaultContext) {
      return context.logic._transition.._transition(me.runtimeType);
    }

    return Transition._().._transition(me.runtimeType);
  }

  Transition handleInput<TInput extends Object>(TState me, TInput input) {
    final handler = _inputHandlers[TInput];

    if (handler == null) {
      return toSelf(me);
    }

    return handler(input);
  }

  /// Call relevant entrance callbacks
  void _callOnEnterHandlers(TState? previous, TState? next) {
    _startOperation(_InternalStateOperation.enter, previous, next);
    _enterHandlers.iterate();
    _endOperation();
  }

  /// Call relevant exit callbacks
  void _callOnExitHandlers(TState? previous, TState? next) {
    _startOperation(_InternalStateOperation.exit, previous, next);
    _exitHandlers.iterateInReverse();
    _endOperation();
  }

  @override
  void handleGenericListItem<TAssociated>(
    GenericList<ObjCallbackNullable> list,
    ObjCallbackNullable item,
  ) {
    switch (_operation!) {
      case _InternalStateOperation.enter:
        if (_next == null) {
          // no state to enter (logic block is shutting down)
          break;
        }

        if (_previous is TAssociated) {
          // already inside this type of state
          break;
        }

        _runTransitionSafely(item, _previous);

      case _InternalStateOperation.exit:
        if (_previous == null) {
          // no state to exit from (logic block is starting up)
          break;
        }

        if (_next is TAssociated) {
          // not actually leaving this type of state
          break;
        }

        _runTransitionSafely(item, _next);
    }
  }

  void _startOperation(
    _InternalStateOperation operation,
    TState? previous,
    TState? next,
  ) {
    _operation = operation;
    _previous = previous;
    _next = next;
  }

  void _endOperation() {
    _operation = null;
    _previous = null;
    _next = null;
  }

  void _runTransitionSafely(ObjCallbackNullable callback, Object? stateArg) {
    final onError = contextAdapter.onError;

    if (onError != null) {
      try {
        callback(stateArg);
      } on Object catch (e) {
        onError(e);
      }

      return;
    }

    // propagate any exceptions if no error handlers are defined
    // (typically means we have a fake context and are running in a unit test)
    callback(stateArg);
  }
}

// This extension allows state class authors to define enter and exit callbacks
// that respect the type hierarchy. Using Dart's extension methods, we can
// declare an extension on a generic parameter that matches a state class and
// capture its exact type as a generic argument.

/// Extension methods on [StateLogic] subclasses for registering
/// hierarchy-aware entrance and exit callbacks.
extension StateLogicExtensions<TDerived extends StateLogic<TState>, TState>
    on TDerived {
  /// Registers a callback invoked when entering this state type, but only
  /// if the previous state is not also of type [TDerived].
  void onEnter(VoidCallback handler) {
    _internalState.onEnter<TDerived>((_) => handler());
  }

  /// Registers a callback invoked when entering this state type, receiving
  /// the previous state (or `null` if there was none). Only fires if the
  /// previous state is not also of type [TDerived].
  void onEnterWithPrevious(ValueCallback<TState?> handler) {
    _internalState
        .onEnter<TDerived>((previous) => handler(previous as TState?));
  }

  /// Registers a callback invoked when exiting this state type, but only
  /// if the next state is not also of type [TDerived].
  void onExit(VoidCallback handler) {
    _internalState.onExit<TDerived>((_) => handler());
  }

  /// Registers a callback invoked when exiting this state type, receiving
  /// the next state (or `null` if there is none). Only fires if the next
  /// state is not also of type [TDerived].
  void onExitWithNext(ValueCallback<TState?> handler) {
    _internalState.onExit<TDerived>((next) => handler(next as TState?));
  }
}
