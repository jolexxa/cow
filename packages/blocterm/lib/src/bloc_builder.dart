import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:blocterm/src/bloc_provider.dart';
import 'package:nocterm/nocterm.dart';

/// Signature for a widget builder based on a bloc state.
typedef BlocWidgetBuilder<S> =
    Component Function(BuildContext context, S state);

/// Condition to control when [BlocBuilder] rebuilds.
typedef BlocBuilderCondition<S> = bool Function(S previous, S current);

/// Builds a component in response to new bloc states.
class BlocBuilder<B extends BlocBase<S>, S> extends StatefulComponent {
  /// Creates a [BlocBuilder] that rebuilds when the bloc state changes.
  const BlocBuilder({
    required this.builder,
    this.bloc,
    this.buildWhen,
    super.key,
  });

  /// Optional bloc instance to use instead of [BlocProvider].
  final B? bloc;

  /// Builder called with the current bloc state.
  final BlocWidgetBuilder<S> builder;

  /// Optional predicate to control rebuilds.
  final BlocBuilderCondition<S>? buildWhen;

  @override
  State<BlocBuilder<B, S>> createState() => _BlocBuilderState<B, S>();
}

class _BlocBuilderState<B extends BlocBase<S>, S>
    extends State<BlocBuilder<B, S>> {
  late B _bloc;
  late S _state;
  StreamSubscription<S>? _subscription;

  @override
  void initState() {
    super.initState();
    _bloc = _resolveBloc();
    _state = _bloc.state;
    _subscribe();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (component.bloc != null) return;
    final nextBloc = _resolveBloc();
    if (nextBloc == _bloc) return;
    _bloc = nextBloc;
    _state = _bloc.state;
    _subscribe();
  }

  @override
  void didUpdateComponent(covariant BlocBuilder<B, S> oldComponent) {
    super.didUpdateComponent(oldComponent);
    final oldBloc = oldComponent.bloc;
    final newBloc = component.bloc;
    if (oldBloc == newBloc) return;
    if (newBloc != null) {
      _bloc = newBloc;
      _state = _bloc.state;
      _subscribe();
      return;
    }
    final nextBloc = _resolveBloc();
    if (nextBloc == _bloc) return;
    _bloc = nextBloc;
    _state = _bloc.state;
    _subscribe();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _subscribe() {
    unawaited(_subscription?.cancel());
    _subscription = _bloc.stream.listen((state) {
      if (!mounted) {
        _state = state;
        return;
      }
      final shouldBuild = component.buildWhen?.call(_state, state) ?? true;
      if (shouldBuild) {
        setState(() {
          _state = state;
        });
      } else {
        _state = state;
      }
    });
  }

  B _resolveBloc() {
    final explicitBloc = component.bloc;
    if (explicitBloc != null) return explicitBloc;
    return BlocProvider.of<B>(context);
  }

  @override
  Component build(BuildContext context) {
    return component.builder(context, _state);
  }
}
