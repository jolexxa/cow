part of 'logic_block.dart';

/// Logic block listener base class.
///
/// Receives callbacks for inputs, states, outputs, and errors that a logic
/// block encounters. For performance, logic blocks cannot be subscribed to
/// with streams or events. Instead, subclass this to listen to every input,
/// state, output, and/or error that a logic block encounters.
abstract class LogicBlockListener<TState extends StateLogic<TState>> {
  bool _isDisposed = false;

  /// Called whenever the logic block receives an input of type [TInput].
  @protected
  void receiveInput<TInput extends Object>(TInput input);

  /// Called whenever the logic block transitions to a new [state].
  @protected
  void receiveState(TState state);

  /// Called whenever the logic block produces an output of type [TOutput].
  @protected
  void receiveOutput<TOutput extends Object>(TOutput output);

  /// Called whenever the logic block encounters an [error].
  @protected
  void receiveError(Object error);

  /// Called during [dispose] to release any resources held by the listener.
  @protected
  void cleanup() {}

  /// Disposes the listener, invoking [cleanup] if not already disposed.
  void dispose() {
    if (_isDisposed) {
      return;
    }

    cleanup();
    _isDisposed = true;
  }
}
