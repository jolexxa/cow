import 'dart:collection';

/// A type-safe data store that maps types to their singleton instances.
///
/// The blackboard pattern allows data to be stored and retrieved by type,
/// ensuring only one instance of each type exists in the store at a time.
class Blackboard {
  /// Creates a new, empty blackboard.
  Blackboard() {
    types = UnmodifiableSetView(_types);
  }

  final Map<Type, Object> _blackboard = {};
  final Set<Type> _types = <Type>{};

  /// An unmodifiable view of all types currently stored in the blackboard.
  late UnmodifiableSetView<Type> types;

  /// Gets the data of type [TData] from the blackboard.
  ///
  /// Throws an [ArgumentError] if no data of the given type exists.
  TData get<TData extends Object>() => _getBlackboardData(TData) as TData;

  /// Gets the data of type [TData] from the blackboard, or `null` if not found.
  TData? getOrNull<TData extends Object>() => _blackboard[TData] as TData?;

  /// Gets the data associated with the given [type] from the blackboard.
  ///
  /// Throws an [ArgumentError] if no data of the given type exists.
  Object getObject(Type type) => _getBlackboardData(type);

  /// Returns `true` if the blackboard contains data of type [TData].
  bool has<TData extends Object>() => hasObject(TData);

  /// Returns `true` if the blackboard contains data for the given [type].
  bool hasObject(Type type) => _blackboard.containsKey(type);

  /// Stores [data] of type [TData] in the blackboard.
  ///
  /// Throws an [ArgumentError] if data of the given type already exists.
  void set<TData extends Object>(TData data) => _setBlackboardData(TData, data);

  /// Stores [data] associated with the given [type] in the blackboard.
  ///
  /// Throws an [ArgumentError] if data of the given type already exists.
  void setObject(Type type, Object data) => _setBlackboardData(type, data);

  /// Overwrites any existing data of type [TData] with the given [data].
  void overwrite<TData extends Object>(TData data) =>
      _overwriteBlackboardData(TData, data);

  /// Overwrites any existing data for the given [type] with [data].
  void overwriteObject(Type type, Object data) =>
      _overwriteBlackboardData(type, data);

  Object _getBlackboardData(Type type) {
    if (_blackboard.containsKey(type)) {
      return _blackboard[type]!;
    }

    throw ArgumentError('No data found for type $type', 'type');
  }

  void _setBlackboardData(Type type, Object data) {
    if (_types.contains(type)) {
      throw ArgumentError('Data for type $type already exists', 'type');
    }

    _types.add(type);
    _blackboard[type] = data;
  }

  void _overwriteBlackboardData(Type type, Object data) {
    _types.add(type);
    _blackboard[type] = data;
  }

  /// Clears all data from the blackboard.
  void clear() {
    _blackboard.clear();
    _types.clear();
  }
}
