import 'package:collections/src/callbacks.dart';

/// Handler invoked for each item in a [GenericList] during iteration.
abstract interface class GenericListHandler<TItem> {
  /// Handles a single item from the list along with its associated generic
  /// type [TAssociated].
  void handleGenericListItem<TAssociated>(
    GenericList<TItem> list,
    TItem item,
  );
}

/// A list that associates an arbitrary generic type with each item. When the
/// list is iterated, the list's [GenericListHandler] will be invoked with
/// the item and its associated generic type.
///
/// Use for situations where you have a long-lived list of items that
/// you want to process via their associated generic type.
final class GenericList<TItem> {
  /// Creates a new [GenericList] with the given [handler].
  GenericList({required this.handler});

  final List<VoidCallback> _items = <VoidCallback>[];

  /// The handler invoked for each item during iteration.
  late final GenericListHandler<TItem> handler;

  /// Adds an [item] to the list, associating it with the generic type
  /// [TAssociated].
  void add<TAssociated>(TItem item) {
    _items.add(() => handler.handleGenericListItem<TAssociated>(this, item));
  }

  /// Iterates the list in order, invoking the handler for each item.
  void iterate() {
    for (var i = 0; i < _items.length; i++) {
      _items[i]();
    }
  }

  /// Iterates the list in reverse order, invoking the handler for each item.
  void iterateInReverse() {
    for (var i = _items.length - 1; i >= 0; i--) {
      _items[i]();
    }
  }
}
