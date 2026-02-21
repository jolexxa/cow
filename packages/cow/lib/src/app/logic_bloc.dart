import 'package:bloc/bloc.dart';
import 'package:logic_blocks/logic_blocks.dart';

/// A [BlocBase] adapter that wraps a [LogicBlock], forwarding state directly.
///
/// [LogicBloc] always returns the current state from the underlying logic
/// block.
class LogicBloc<TState extends StateLogic<TState>> extends BlocBase<TState> {
  LogicBloc(this.logic) : super(logic.start()) {
    binding = logic.bind()..onState<TState>(emit);
  }

  final LogicBlock<TState> logic;

  /// The binding to the logic block. Subclasses can add output handlers.
  late final LogicBlockBinding<TState> binding;

  @override
  TState get state => logic.value;

  /// Sends an input to the underlying logic block.
  TState input<TInput extends Object>(TInput input) => logic.input(input);

  /// Gets a value from the logic block's blackboard.
  TData get<TData extends Object>() => logic.get<TData>();

  @override
  Future<void> close() async {
    binding.dispose();
    logic.stop();
    return super.close();
  }
}
