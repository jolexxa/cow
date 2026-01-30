import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:blocterm/src/bloc_provider.dart';
import 'package:nocterm/nocterm.dart';

/// Signature for a listener invoked on bloc state changes.
typedef BlocWidgetListener<S> = void Function(BuildContext context, S state);

/// Condition to control when [BlocListener] notifies.
typedef BlocListenerCondition<S> = bool Function(S previous, S current);

/// Invokes [listener] in response to new bloc states.
class BlocListener<B extends BlocBase<S>, S> extends StatefulComponent {
  /// Creates a [BlocListener] that invokes [listener] on bloc state changes.
  const BlocListener({
    required this.listener,
    required this.child,
    this.bloc,
    this.listenWhen,
    super.key,
  });

  /// Optional bloc instance to use instead of [BlocProvider].
  final B? bloc;

  /// Listener called with the current bloc state.
  final BlocWidgetListener<S> listener;

  /// Optional predicate to control notifications.
  final BlocListenerCondition<S>? listenWhen;

  /// Child component.
  final Component child;

  @override
  State<BlocListener<B, S>> createState() => _BlocListenerState<B, S>();
}

class _BlocListenerState<B extends BlocBase<S>, S>
    extends State<BlocListener<B, S>> {
  late B _bloc;
  late S _previousState;
  StreamSubscription<S>? _subscription;

  @override
  void initState() {
    super.initState();
    _bloc = _resolveBloc();
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
    _previousState = _bloc.state;
    _subscribe();
  }

  @override
  void didUpdateComponent(covariant BlocListener<B, S> oldComponent) {
    super.didUpdateComponent(oldComponent);
    final oldBloc = oldComponent.bloc;
    final newBloc = component.bloc;
    if (oldBloc == newBloc) return;
    if (newBloc != null) {
      _bloc = newBloc;
      _previousState = _bloc.state;
      _subscribe();
      return;
    }
    final nextBloc = _resolveBloc();
    if (nextBloc == _bloc) return;
    _bloc = nextBloc;
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
      final shouldListen =
          component.listenWhen?.call(_previousState, state) ?? true;
      if (shouldListen) {
        component.listener(context, state);
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
    return component.child;
  }
}
