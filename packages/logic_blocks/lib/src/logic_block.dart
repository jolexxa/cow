import 'package:collections/collections.dart';
import 'package:meta/meta.dart';

part 'context.dart';
part 'logic_block_binding.dart';
part 'logic_block_fake_binding.dart';
part 'logic_block_listener.dart';
part 'state_logic.dart';

/// Represents a transition to a new state type.
///
/// Transitions are reused internally to avoid allocating new objects for each
/// state change. Do not call `to` more than once per transition.
class Transition {
  Transition._();

  Type _stateType = Object;
  bool _isTransitioning = false;

  /// The type of state being transitioned to.
  Type get stateType => _stateType;

  void _transition(Type stateType) {
    if (_isTransitioning) {
      throw Exception(
        'Invalid use of To<TStateType>() — do not call this '
        'method more than once per transition.',
      );
    }

    _stateType = stateType;
    _isTransitioning = true;
  }

  void _done() {
    _isTransitioning = false;
  }
}

/// Base class for all logic blocks. Provides access to the [blackboard] and
/// the current state as an [Object].
abstract base class LogicBlockBase {
  /// The blackboard data store shared across states.
  abstract final Blackboard blackboard;

  /// The current state as an untyped [Object], or `null` if the logic block
  /// has not been started.
  Object? get valueAsObject;
}

/// {@template logic_blocks}
/// A logic block. Logic blocks are machines that receive input, maintain a
/// single state, and produce outputs. They can be used as simple
/// input-to-state reducers or built upon to create hierarchical state
/// machines.
/// {@endtemplate}
abstract base class LogicBlock<TState extends StateLogic<TState>>
    extends LogicBlockBase implements GenericQueueHandler {
  /// {@macro logic_blocks}
  LogicBlock() {
    _inputs = GenericQueue(handler: this);
    _context = _DefaultContext<TState>(this);
  }

  /// Creates a [LogicBlockFakeBinding] for testing binding callbacks without
  /// a real logic block instance.
  static LogicBlockFakeBinding
      createFakeBinding<TState extends StateLogic<TState>>() =>
          LogicBlockFakeBinding<TState>();

  /// Returns `true` if [a] and [b] are equivalent — that is, identical,
  /// both null, equal, or of the same runtime type.
  static bool isEquivalent(Object? a, Object? b) {
    return identical(a, b) ||
        (a == null && b == null) ||
        (a != null &&
            b != null &&
            ((a == b) || (a.runtimeType == b.runtimeType)));
  }

  /// Returns a [Transition] representing the initial state of the logic block.
  ///
  /// Implementations must override this to specify which state the logic block
  /// starts in by calling [to].
  Transition getInitialState();

  @override
  final Blackboard blackboard = Blackboard();

  /// The current state of the logic block. Accessing this before the logic
  /// block has been started will trigger initialization.
  TState get value => _value ?? _flush();

  /// Whether the logic block is currently processing inputs.
  bool get isProcessing => _busy > 0;

  @override
  Object? get valueAsObject => _value;

  late final Context _context;
  late final Set<LogicBlockListener<TState>> _listeners = {};
  late GenericQueue _inputs;
  int _busy = 0;
  bool _started = false;
  Object? _restoredState;
  TState? _value;

  // Dart doesn't have structs, so we just use a single transition instance to
  // avoid allocating a new object for each transition.
  final Transition _transition = Transition._();

  /// Creates a new [LogicBlockBinding] that listens to this logic block.
  ///
  /// Always dispose the returned binding when you are finished with it.
  LogicBlockBinding<TState> bind() => _LogicBlockBinding<TState>(this);

  /// Starts the logic block by entering the initial state and returns it.
  ///
  /// Has no effect if the logic block is already processing or has already
  /// been started.
  TState start() {
    if (isProcessing || _value != null) {
      return _value!;
    }

    return _flush();
  }

  /// Stops the logic block, calling exit and detach callbacks on the current
  /// state before clearing the input queue.
  ///
  /// Has no effect if the logic block is currently processing or has not been
  /// started.
  void stop() {
    if (isProcessing || _value == null) {
      return;
    }

    // Repeatedly exit and detach the current state until there is none.
    _changeState(null);

    _inputs.clear();

    // A state finally exited and detached without queuing additional inputs.
    _value = null;

    _started = false;
    onStop();
  }

  /// Called after the logic block has been started for the first time.
  /// Override to perform setup after initial state entry.
  @protected
  void onStart() {}

  /// Called after the logic block has been stopped.
  /// Override to perform teardown after final state exit.
  @protected
  void onStop() {}

  /// Forcibly resets the logic block to the given [state], exiting and
  /// detaching the current state.
  ///
  /// Throws a [StateError] if called while the logic block is processing
  /// inputs.
  TState forceReset(TState state) {
    if (isProcessing) {
      throw StateError(
        'Cannot force reset a logic block while it is processing inputs. '
        "Do not call ForceReset() from inside a logic block's own state.",
      );
    }

    _changeState(state);

    return _flush();
  }

  /// Adds an [input] value to the logic block's internal input queue.
  ///
  /// If the logic block is already processing, the input is enqueued and
  /// will be handled after the current input finishes. Returns the current
  /// state.
  TState input<TInput extends Object>(TInput input) {
    if (isProcessing) {
      _inputs.enqueue(input);
      return value;
    }

    return _processInputs<TInput>(input);
  }

  /// Gets a value of type [TData] from the blackboard.
  TData get<TData extends Object>() => blackboard.get<TData>();

  /// Sets a value of type [TData] on the blackboard.
  void set<TData extends Object>(TData data) => blackboard.set(data);

  /// Restores this logic block's state and blackboard from another [logic]
  /// block of the same type.
  ///
  /// Stops this logic block first, then copies the blackboard and state from
  /// the source. Throws a [StateError] if [logic] has not been started.
  void restoreFrom(LogicBlock<TState> logic) {
    final state = logic.valueAsObject ?? logic._restoredState;

    if (state == null) {
      throw StateError(
        "Cannot restore from the logic block $logic that hasn't been started "
        'yet.',
      );
    }

    stop();

    for (final type in logic.blackboard.types) {
      blackboard.overwriteObject(type, logic.blackboard.getObject(type));
    }

    final stateType = state.runtimeType;

    blackboard.overwriteObject(stateType, state);
    restoreState(state);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is! LogicBlockBase) {
      return false;
    }

    if (runtimeType != other.runtimeType) {
      return false;
    }

    if (!isEquivalent(valueAsObject, other.valueAsObject)) {
      return false;
    }

    final types = blackboard.types;
    final otherTypes = other.blackboard.types;

    if (types.length != otherTypes.length) {
      return false;
    }

    for (final type in types) {
      if (!otherTypes.contains(type)) {
        return false;
      }

      final obj1 = blackboard.getObject(type);
      final obj2 = other.blackboard.getObject(type);

      if (isEquivalent(obj1, obj2)) {
        continue;
      }

      return false;
    }

    return true;
  }

  @override
  int get hashCode => Object.hash(valueAsObject, blackboard.types);

  /// Called whenever an error is reported by a state. Override to handle
  /// errors produced during state logic execution.
  @protected
  void handleError(Object e) {}

  /// Defines a transition to the state of type [TStateType] stored on the
  /// blackboard.
  @protected
  Transition to<TStateType extends TState>() =>
      _transition.._transition(TStateType);

  @override
  @internal
  void handleGenericQueueItem<TInput extends Object>(
    GenericQueue queue,
    TInput input,
  ) {
    // process an input
    final value = _value!;

    final transition = value.handleInput<TInput>(input).._done();

    _announceInput<TInput>(input);

    final state = blackboard.getObject(transition.stateType) as TState;

    if (!_canChangeState(state)) {
      // state hasn't changed — new state is the same as the current state
      return;
    }

    _changeState(state);
  }

  @internal
  void restoreState(Object state) {
    if (_value != null) {
      throw StateError(
        'Cannot restore a state once the logic block is already running.',
      );
    }

    _restoredState = state as TState;
  }

  TState _processInputs<TInput extends Object>([TInput? input]) {
    _busy++;

    if (_value == null) {
      // no state yet — let's get started
      _changeState(
        _restoredState as TState? ??
            blackboard.getObject(_getInitialState()) as TState,
      );
      _restoredState = null;

      if (!_started) {
        _started = true;
        onStart();
      }
    }

    // process any first input
    if (input != null) {
      handleGenericQueueItem(_inputs, input);
    }

    while (_inputs.isNotEmpty) {
      _inputs.dequeue();
    }

    _busy--;

    return _value!;
  }

  Type _getInitialState() {
    final transition = getInitialState().._done();

    return transition.stateType;
  }

  TState _flush() {
    if (_value == null) {
      // Someday: restore blackboard if previously serialized
    }

    return _processInputs<Object>();
  }

  void _changeState(TState? state) {
    _busy++;
    final previous = _value;

    previous?.exit(state);
    previous?.detach();

    _value = state;

    final stateIsDifferent = _canChangeState(previous);

    if (state != null) {
      state
        ..attach(_context)
        ..enter(previous);

      if (stateIsDifferent) {
        _announceState(state);
      }
    }

    _busy--;
  }

  void _announceInput<TInput extends Object>(TInput input) {
    for (final listener in _listeners) {
      listener.receiveInput<TInput>(input);
    }
  }

  void _announceState(TState state) {
    for (final listener in _listeners) {
      listener.receiveState(state);
    }
  }

  void _announceOutput<TOutput extends Object>(TOutput output) {
    for (final listener in _listeners) {
      listener.receiveOutput<TOutput>(output);
    }
  }

  void _announceError(Object e) {
    for (final listener in _listeners) {
      listener.receiveError(e);
    }
  }

  void _addError(Object e) {
    _announceError(e);
    handleError(e);
  }

  void _output<TOutput extends Object>(TOutput output) =>
      _announceOutput<TOutput>(output);

  void _addListener(LogicBlockListener<TState> listener) =>
      _listeners.add(listener);

  void _removeListener(LogicBlockListener<TState> listener) =>
      _listeners.remove(listener);

  // we can change states if the new state has a different runtime type
  bool _canChangeState(TState? state) => !isEquivalent(state, _value);
}
