import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:blocterm/src/bloc_builder.dart';
import 'package:blocterm/src/bloc_listener.dart';
import 'package:blocterm/src/bloc_provider.dart';
import 'package:nocterm/nocterm.dart';

/// Combines [BlocBuilder] and [BlocListener] in one component.
class BlocConsumer<B extends BlocBase<S>, S> extends StatefulComponent {
  /// Creates a [BlocConsumer] that rebuilds and listens to bloc changes.
  const BlocConsumer({
    required this.builder,
    required this.listener,
    this.bloc,
    this.buildWhen,
    this.listenWhen,
    super.key,
  });

  /// Optional bloc instance to use instead of [BlocProvider].
  final B? bloc;

  /// Builder called with the current bloc state.
  final BlocWidgetBuilder<S> builder;

  /// Listener called with the current bloc state.
  final BlocWidgetListener<S> listener;

  /// Optional predicate to control rebuilds.
  final BlocBuilderCondition<S>? buildWhen;

  /// Optional predicate to control notifications.
  final BlocListenerCondition<S>? listenWhen;

  @override
  State<BlocConsumer<B, S>> createState() => _BlocConsumerState<B, S>();
}

class _BlocConsumerState<B extends BlocBase<S>, S>
    extends State<BlocConsumer<B, S>> {
  late B _bloc;
  late S _state;
  late S _previousState;
  StreamSubscription<S>? _subscription;

  @override
  void initState() {
    super.initState();
    _bloc = _resolveBloc();
    _state = _bloc.state;
    _previousState = _bloc.state;
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
    _previousState = _bloc.state;
    _subscribe();
  }

  @override
  void didUpdateComponent(covariant BlocConsumer<B, S> oldComponent) {
    super.didUpdateComponent(oldComponent);
    final oldBloc = oldComponent.bloc;
    final newBloc = component.bloc;
    if (oldBloc == newBloc) return;
    if (newBloc != null) {
      _bloc = newBloc;
      _state = _bloc.state;
      _previousState = _bloc.state;
      _subscribe();
      return;
    }
    final nextBloc = _resolveBloc();
    if (nextBloc == _bloc) return;
    _bloc = nextBloc;
    _state = _bloc.state;
    _previousState = _bloc.state;
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
        _previousState = state;
        return;
      }

      final shouldListen =
          component.listenWhen?.call(_previousState, state) ?? true;
      if (shouldListen) {
        component.listener(context, state);
      }

      final shouldBuild =
          component.buildWhen?.call(_previousState, state) ?? true;
      if (shouldBuild) {
        setState(() {
          _state = state;
        });
      } else {
        _state = state;
      }
      _previousState = state;
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
