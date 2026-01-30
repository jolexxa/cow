import 'package:blocterm/blocterm.dart';

/// Thrown when a [BlocProvider] lookup fails in the component tree.
class BlocProviderNotFoundException implements Exception {
  /// Creates an exception for missing [BlocProvider] lookups.
  BlocProviderNotFoundException(this.type);

  /// The bloc type that failed to resolve from the component tree.
  final Type type;

  @override
  String toString() {
    return 'BlocProvider<$type> not found in the component tree.';
  }
}
