part of 'logic_block.dart';

/// Logic block execution context provided to each state.
///
/// The context allows states to interact with their parent logic block by
/// adding inputs, producing outputs, reading blackboard data, and reporting
/// errors.
abstract interface class Context {
  /// Adds an input value to the logic block's internal input queue.
  void input<TInput extends Object>(TInput input);

  /// Produces a logic block output value.
  void output<TOutput extends Object>(TOutput output);

  /// Gets a value of type [TData] from the logic block's blackboard.
  TData get<TData extends Object>();

  /// Adds an error to the logic block. Errors are immediately processed by
  /// the logic block's [LogicBlock.handleError] callback.
  void addError(Object e);

  /// Whether the logic block is currently running and can accept inputs.
  bool get isStarted;

  /// Tracks a [Future] so that [LogicBlock.task] will not complete until
  /// [future] has finished.
  void trackFuture(Future<void> future);
}

final class _DefaultContext<TState extends StateLogic<TState>> extends Context {
  _DefaultContext(this.logic);

  final LogicBlock<TState> logic;

  @override
  void input<TInput extends Object>(TInput input) => logic.input(input);

  @override
  void output<TOutput extends Object>(TOutput output) => logic._output(output);

  @override
  TData get<TData extends Object>() => logic.get<TData>();

  @override
  void addError(Object e) => logic._addError(e);

  @override
  bool get isStarted => logic.isStarted;

  @override
  void trackFuture(Future<void> future) =>
      logic._futureTracker.trackFuture(future);
}

final class _ContextAdapter implements Context {
  _ContextAdapter();

  Context? context;
  bool _active = true; // Starts active; deactivate() on detach

  void adapt(Context context) {
    this.context = context;
    _active = true;
  }

  void deactivate() => _active = false;

  bool get isActive => _active && context != null;

  @override
  bool get isStarted => context?.isStarted ?? false;

  ValueCallback<Object>? get onError {
    final context = this.context;
    return (context != null && context is _DefaultContext
        ? context.addError
        : null);
  }

  @override
  void input<TInput extends Object>(TInput input) {
    // Ignore inputs from inactive (detached) states.
    if (!_active) return;

    final context = this.context;

    if (context == null) {
      throw Exception(
        'Cannot add input to a logic block with an uninitialized context.',
      );
    }

    context.input(input);
  }

  @override
  void output<TOutput extends Object>(TOutput output) {
    // Ignore outputs from inactive (detached) states.
    if (!_active) return;

    final context = this.context;

    if (context == null) {
      throw Exception(
        'Cannot add output to a logic block with an uninitialized context.',
      );
    }

    context.output(output);
  }

  @override
  TData get<TData extends Object>() {
    final context = this.context;

    if (context == null) {
      throw Exception(
        'Cannot get value from a logic block with an uninitialized context.',
      );
    }

    return context.get<TData>();
  }

  @override
  void addError(Object e) {
    // Ignore errors from inactive (detached) states.
    if (!_active) return;

    final context = this.context;

    if (context == null) {
      throw Exception(
        'Cannot add error to a logic block with an uninitialized context.',
      );
    }

    context.addError(e);
  }

  @override
  void trackFuture(Future<void> future) {
    context?.trackFuture(future);
  }
}

/// Fake logic block context provided for testing convenience.
///
/// Records all inputs, outputs, and errors that states produce, allowing
/// test assertions against them. Use [StateLogic.createFakeContext] to
/// attach a fake context to a state under test.
final class FakeContext implements Context {
  /// Creates a new [FakeContext].
  FakeContext();

  /// The simulated logic block status. Defaults to [LogicBlockStatus.started].
  LogicBlockStatus status = LogicBlockStatus.started;

  @override
  bool get isStarted => status == LogicBlockStatus.started;

  /// A [Future] that completes when all tracked async operations have
  /// finished. Use this to await in-flight [StatefulFuture] work in tests.
  Future<void> get task => _futureTracker.future;

  /// Inputs that have been added by the state under test.
  Iterable<Object> get inputs => _inputs;

  /// Outputs that have been produced by the state under test.
  Iterable<Object> get outputs => _outputs;

  /// Errors that have been reported by the state under test.
  Iterable<Object> get errors => _errors;

  final FutureTracker _futureTracker = FutureTracker();
  final List<Object> _inputs = [];
  final List<Object> _outputs = [];
  final Blackboard _blackboard = Blackboard();
  final List<Object> _errors = [];

  @override
  void input<TInput extends Object>(TInput input) => _inputs.add(input);

  @override
  void output<TOutput extends Object>(TOutput output) => _outputs.add(output);

  @override
  TData get<TData extends Object>() => _blackboard.get<TData>();

  @override
  void addError(Object e) => _errors.add(e);

  @override
  void trackFuture(Future<void> future) => _futureTracker.trackFuture(future);

  /// Sets a value of type [TData] in the fake blackboard.
  void set<TData extends Object>(TData data) => _blackboard.set(data);

  /// Clears all recorded inputs, outputs, errors, and blackboard data.
  void reset() {
    _futureTracker.reset();
    _inputs.clear();
    _outputs.clear();
    _errors.clear();
    _blackboard.clear();
  }

  @override
  bool operator ==(Object other) => true;

  @override
  int get hashCode => Object.hash(_inputs, _outputs, _errors);
}
