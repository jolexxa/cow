import 'package:collections/collections.dart';
import 'package:test/test.dart';

void main() {
  group('$Blackboard', () {
    late Blackboard blackboard;

    setUp(() {
      blackboard = Blackboard();
    });

    test('set<T> + get<T> round-trip', () {
      blackboard.set<String>('hello');
      expect(blackboard.get<String>(), 'hello');
    });

    test('setObject + getObject round-trip', () {
      blackboard.setObject(int, 42);
      expect(blackboard.getObject(int), 42);
    });

    test('get<T> throws ArgumentError on missing type', () {
      expect(() => blackboard.get<String>(), throwsArgumentError);
    });

    test('getObject throws ArgumentError on missing type', () {
      expect(() => blackboard.getObject(String), throwsArgumentError);
    });

    test('set<T> throws ArgumentError on duplicate type', () {
      blackboard.set<String>('first');
      expect(() => blackboard.set<String>('second'), throwsArgumentError);
    });

    test('setObject throws ArgumentError on duplicate type', () {
      blackboard.setObject(String, 'first');
      expect(() => blackboard.setObject(String, 'second'), throwsArgumentError);
    });

    test('has<T> returns true when type exists', () {
      blackboard.set<String>('hi');
      expect(blackboard.has<String>(), isTrue);
    });

    test('has<T> returns false when type missing', () {
      expect(blackboard.has<String>(), isFalse);
    });

    test('hasObject returns true when type exists', () {
      blackboard.setObject(int, 1);
      expect(blackboard.hasObject(int), isTrue);
    });

    test('hasObject returns false when type missing', () {
      expect(blackboard.hasObject(int), isFalse);
    });

    test('overwrite<T> works without prior data', () {
      blackboard.overwrite<String>('new');
      expect(blackboard.get<String>(), 'new');
    });

    test('overwrite<T> works with prior data', () {
      blackboard
        ..set<String>('old')
        ..overwrite<String>('new');
      expect(blackboard.get<String>(), 'new');
    });

    test('overwriteObject works without prior data', () {
      blackboard.overwriteObject(int, 99);
      expect(blackboard.getObject(int), 99);
    });

    test('overwriteObject works with prior data', () {
      blackboard
        ..setObject(int, 1)
        ..overwriteObject(int, 2);
      expect(blackboard.getObject(int), 2);
    });

    test('types returns correct set of stored types', () {
      blackboard
        ..set<String>('a')
        ..set<int>(1);

      expect(blackboard.types, containsAll([String, int]));
      expect(blackboard.types.length, 2);
    });

    test('clear empties everything', () {
      blackboard
        ..set<String>('a')
        ..set<int>(1)
        ..clear();

      expect(blackboard.has<String>(), isFalse);
      expect(blackboard.has<int>(), isFalse);
      expect(blackboard.types, isEmpty);
    });
  });
}
