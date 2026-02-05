// For clarity.
// ignore_for_file: cascade_invocations

import 'package:collections/collections.dart';
import 'package:test/test.dart';

class TestQueueHandler implements GenericQueueHandler {
  final List<Object> received = [];
  final List<Type> receivedTypes = [];

  @override
  void handleGenericQueueItem<TItem extends Object>(
    GenericQueue queue,
    TItem value,
  ) {
    received.add(value);
    receivedTypes.add(TItem);
  }
}

void main() {
  group('$GenericQueue', () {
    late TestQueueHandler handler;
    late GenericQueue queue;

    setUp(() {
      handler = TestQueueHandler();
      queue = GenericQueue(handler: handler);
    });

    test('enqueue + dequeue FIFO ordering', () {
      queue
        ..enqueue<String>('a')
        ..enqueue<String>('b')
        ..enqueue<String>('c');

      // enqueue addFirst's, dequeue removeLast's → FIFO
      queue
        ..dequeue()
        ..dequeue()
        ..dequeue();

      expect(handler.received, ['a', 'b', 'c']);
    });

    test('mixed types preserve type info', () {
      queue
        ..enqueue<String>('hello')
        ..enqueue<int>(42);

      queue
        ..dequeue()
        ..dequeue();

      expect(handler.received, ['hello', 42]);
      expect(handler.receivedTypes, [String, int]);
    });

    test('push + pop LIFO ordering', () {
      queue
        ..push<String>('a')
        ..push<String>('b')
        ..push<String>('c');

      // pop takes from the front (earliest pushed)
      queue
        ..pop()
        ..pop()
        ..pop();

      expect(handler.received, ['a', 'b', 'c']);
    });

    test('isNotEmpty true when items exist, false when empty', () {
      expect(queue.isNotEmpty, isFalse);

      queue.enqueue<String>('x');
      expect(queue.isNotEmpty, isTrue);

      queue.dequeue();
      expect(queue.isNotEmpty, isFalse);
    });

    test('dequeue on empty queue is a no-op', () {
      queue.dequeue();
      expect(handler.received, isEmpty);
    });

    test('pop on empty queue is a no-op', () {
      queue.pop();
      expect(handler.received, isEmpty);
    });

    test('clear empties everything', () {
      queue
        ..enqueue<String>('a')
        ..enqueue<int>(1);

      queue.clear();

      expect(queue.isNotEmpty, isFalse);
    });

    test('multiple items of same type reuse queue', () {
      queue
        ..enqueue<String>('a')
        ..enqueue<String>('b');

      queue
        ..dequeue()
        ..dequeue();

      expect(handler.received, ['a', 'b']);
      expect(handler.receivedTypes, [String, String]);
    });

    test('enqueue + pop mixed ordering', () {
      queue
        ..enqueue<String>('first-enqueue')
        ..push<String>('first-push');

      // pop takes from front (first-enqueue was addFirst'd)
      queue.pop();
      expect(handler.received.last, 'first-enqueue');

      // dequeue takes from back (first-push was addLast'd)
      queue.dequeue();
      expect(handler.received.last, 'first-push');
    });
  });
}
