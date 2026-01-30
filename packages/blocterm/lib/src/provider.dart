import 'package:nocterm/nocterm.dart';

/// A provider that supplies a value of type [T] to its descendants.
class Provider<T> extends InheritedComponent {
  /// Creates a [Provider] with the given [value] and [child].
  const Provider({
    required this.value,
    required super.child,
  });

  /// The value provided to descendants.
  final T value;

  /// Retrieves the nearest [Provider] of type [T] from the [context].
  static T of<T>(BuildContext context) {
    return context.dependOnInheritedComponentOfExactType<Provider<T>>()!.value;
  }

  @override
  bool updateShouldNotify(Provider<T> oldComponent) {
    return value != oldComponent.value;
  }
}
