import 'package:collections/collections.dart';
import 'package:test/test.dart';

class TestListHandler implements GenericListHandler<String> {
  final List<String> received = [];
  final List<Type> receivedTypes = [];

  @override
  void handleGenericListItem<TAssociated>(
    GenericList<String> list,
    String item,
  ) {
    received.add(item);
    receivedTypes.add(TAssociated);
  }
}

void main() {
  group('$GenericList', () {
    late TestListHandler handler;
    late GenericList<String> list;

    setUp(() {
      handler = TestListHandler();
      list = GenericList(handler: handler);
    });

    test('add + iterate forward order', () {
      list
        ..add<int>('a')
        ..add<double>('b')
        ..add<String>('c')
        ..iterate();

      expect(handler.received, ['a', 'b', 'c']);
      expect(handler.receivedTypes, [int, double, String]);
    });

    test('add + iterateInReverse reverse order', () {
      list
        ..add<int>('a')
        ..add<double>('b')
        ..add<String>('c')
        ..iterateInReverse();

      expect(handler.received, ['c', 'b', 'a']);
      expect(handler.receivedTypes, [String, double, int]);
    });

    test('iterate on empty list is no-op', () {
      list.iterate();
      expect(handler.received, isEmpty);
    });

    test('iterateInReverse on empty list is no-op', () {
      list.iterateInReverse();
      expect(handler.received, isEmpty);
    });

    test('handler receives correct associated type via generic', () {
      list
        ..add<bool>('item')
        ..iterate();

      expect(handler.receivedTypes.single, bool);
    });
  });
}
