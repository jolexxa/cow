part of 'logic_block.dart';

/// A fake binding for testing logic block bindings without a real logic block.
///
/// Allows manually dispatching states, inputs, outputs, and errors to verify
/// that binding callbacks are invoked correctly.
final class LogicBlockFakeBinding<TState extends StateLogic<TState>>
    extends _LogicBlockBindingBase<TState> {
  /// Simulates a state change to [state], invoking any matching state
  /// callbacks.
  void setState(TState state) => super.receiveState(state);

  /// Simulates receiving an input of type [TInput], invoking any matching
  /// input callbacks.
  void input<TInput extends Object>(TInput input) =>
      super.receiveInput<TInput>(input);

  /// Simulates producing an output of type [TOutput], invoking any matching
  /// output callbacks.
  void output<TOutput extends Object>(TOutput output) =>
      super.receiveOutput<TOutput>(output);

  /// Simulates an error, invoking any matching error callbacks.
  void addError(Object error) => super.receiveError(error);
}
