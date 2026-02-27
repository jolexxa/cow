// Fluent API — returning `this` is intentional.
// ignore_for_file: avoid_returning_this
part of 'logic_block.dart';

/// A wrapper around a [Future] that delivers its result as an input to a
/// logic block.
///
/// Use [StateLogic.async] to create instances. Chain [input] and
/// [errorInput] to define which inputs to fire on success or failure.
///
/// If the logic block has been stopped or disposed by the time the future
/// completes, the input is silently discarded.
///
/// Inputs are delivered even if the originating state has been replaced
/// (detached), because async work should not be lost on state transitions.
class StatefulFuture<T> {
  StatefulFuture._(this._adapter, Future<T> future) {
    final continuation = future.then(
      (value) {
        final cb = _onSuccess;
        if (cb != null) _inputIfRunning(cb(value));
      },
      onError: (Object error) {
        final cb = _onError;
        if (cb != null) _inputIfRunning(cb(error));
      },
    );

    _adapter.trackFuture(continuation);
  }

  void _inputIfRunning(Object input) {
    if (!_adapter.isStarted) return;
    _adapter.context!.input(input);
  }

  final _ContextAdapter _adapter;
  Object Function(T)? _onSuccess;
  Object Function(Object)? _onError;

  /// Registers a callback that converts the future's success value into an
  /// input for the logic block.
  StatefulFuture<T> input(Object Function(T value) toInput) {
    _onSuccess = toInput;
    return this;
  }

  /// Registers a callback that converts the future's error into an input
  /// for the logic block.
  StatefulFuture<T> errorInput(Object Function(Object error) toInput) {
    _onError = toInput;
    return this;
  }
}
