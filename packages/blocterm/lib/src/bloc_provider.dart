import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:blocterm/src/errors.dart';
import 'package:nocterm/nocterm.dart';

/// Provides a bloc to descendant components.
class BlocProvider<B extends BlocBase<Object?>> extends StatefulComponent {
  /// Creates a [BlocProvider] that owns and disposes the bloc.
  const BlocProvider.create({
    required this.create,
    required this.child,
    super.key,
  }) : value = null;

  /// Creates a [BlocProvider] that exposes [value] to its descendants.
  const BlocProvider.value({
    required this.value,
    required this.child,
    super.key,
  }) : create = null;

  /// The bloc instance exposed to descendants.
  final B? value;

  /// Builder used to create a bloc owned by the provider.
  final B Function(BuildContext context)? create;

  /// The child component.
  final Component child;

  /// Retrieves a bloc of type [B] from the nearest [BlocProvider].
  static B of<B extends BlocBase<Object?>>(
    BuildContext context, {
    bool listen = true,
  }) {
    _BlocProviderInherited<B>? provider;
    if (listen) {
      provider = context
          .dependOnInheritedComponentOfExactType<_BlocProviderInherited<B>>();
    } else {
      final element = context
          .getElementForInheritedComponentOfExactType<
            _BlocProviderInherited<B>
          >();
      provider = element?.component as _BlocProviderInherited<B>?;
    }

    if (provider == null) {
      throw BlocProviderNotFoundException(B);
    }
    return provider.bloc;
  }

  @override
  State<BlocProvider<B>> createState() => _BlocProviderState<B>();
}

final class _BlocProviderState<B extends BlocBase<Object?>>
    extends State<BlocProvider<B>> {
  B? _bloc;
  var _ownsBloc = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureBloc();
  }

  @override
  void didUpdateComponent(covariant BlocProvider<B> oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (component.create != null) {
      if (oldComponent.create == component.create) {
        return;
      }
      final oldBloc = _bloc;
      _bloc = component.create!(context);
      _ownsBloc = true;
      if (oldComponent.create != null && oldBloc != null) {
        unawaited(oldBloc.close());
      }
      return;
    }

    if (oldComponent.create != null && _ownsBloc) {
      final oldBloc = _bloc;
      _bloc = component.value;
      _ownsBloc = false;
      if (oldBloc != null) {
        unawaited(oldBloc.close());
      }
      return;
    }

    if (oldComponent.value != component.value) {
      _bloc = component.value;
    }
  }

  @override
  void dispose() {
    if (_ownsBloc) {
      final bloc = _bloc;
      if (bloc != null) {
        unawaited(bloc.close());
      }
    }
    super.dispose();
  }

  void _ensureBloc() {
    if (component.create != null) {
      _bloc ??= component.create!(context);
      _ownsBloc = true;
      return;
    }
    _bloc = component.value;
    _ownsBloc = false;
  }

  @override
  Component build(BuildContext context) {
    _ensureBloc();
    final bloc = _bloc;
    if (bloc == null) {
      return component.child;
    }
    return _BlocProviderInherited<B>(
      bloc: bloc,
      child: component.child,
    );
  }
}

final class _BlocProviderInherited<B extends BlocBase<Object?>>
    extends InheritedComponent {
  const _BlocProviderInherited({
    required this.bloc,
    required super.child,
    super.key,
  });

  final B bloc;

  @override
  bool updateShouldNotify(covariant _BlocProviderInherited<B> oldComponent) {
    return bloc != oldComponent.bloc;
  }
}
