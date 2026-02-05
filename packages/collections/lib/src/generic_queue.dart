import 'dart:collection';

/// Handler invoked when an item is dequeued from a [GenericQueue].
abstract interface class GenericQueueHandler {
  /// Handles a single dequeued item along with its generic type [TItem].
  void handleGenericQueueItem<TItem extends Object>(
    GenericQueue queue,
    TItem value,
  );
}

abstract class _GenericQueueItemBase {
  void handleValue(GenericQueue queue, GenericQueueHandler handler);
  void clear();
}

class _GenericQueueItem<TItem extends Object> extends _GenericQueueItemBase {
  final Queue<TItem> _queue = Queue<TItem>();

  void enqueue(TItem item) => _queue.add(item);

  @override
  void clear() => _queue.clear();

  @override
  void handleValue(GenericQueue queue, GenericQueueHandler handler) =>
      handler.handleGenericQueueItem(queue, _queue.removeFirst());
}

/// A queue that preserves the generic type of each enqueued item.
///
/// Items are grouped into per-type sub-queues. When dequeued, the
/// [GenericQueueHandler] receives the item along with its original generic
/// type, allowing type-safe processing without losing generic information.
final class GenericQueue {
  /// Creates a new [GenericQueue] with the given [handler].
  GenericQueue({required this.handler});

  /// The handler invoked when an item is dequeued.
  final GenericQueueHandler handler;
  final Queue<Type> _queueSelectorQueue = Queue<Type>();
  final Map<Type, _GenericQueueItemBase> _queues = {};

  /// Enqueues a [value] at the front of the queue (LIFO relative to
  /// [dequeue]).
  void enqueue<TItem extends Object>(TItem value) => _insert(value);

  /// Dequeues and processes the most recently enqueued item.
  void dequeue() => _dequeue();

  /// Pushes a [value] to the back of the queue.
  void push<TItem extends Object>(TItem value) => _insert(value, false);

  /// Pops and processes the earliest enqueued item.
  void pop() => _dequeue(true);

  /// Whether the queue contains any items.
  bool get isNotEmpty => _queueSelectorQueue.isNotEmpty;

  /// Removes all items from the queue.
  void clear() {
    _queueSelectorQueue.clear();

    for (final queue in _queues.values) {
      queue.clear();
    }
  }

  void _dequeue([bool first = false]) {
    if (!isNotEmpty) {
      return;
    }

    final type = first
        ? _queueSelectorQueue.removeFirst()
        : _queueSelectorQueue.removeLast();

    _queues[type]!.handleValue(this, handler);
  }

  void _insert<TItem extends Object>(TItem value, [bool first = true]) {
    late _GenericQueueItem<TItem> queue;

    if (!_queues.containsKey(TItem)) {
      queue = _GenericQueueItem<TItem>();
      _queues[TItem] = queue;
    } else {
      queue = _queues[TItem]! as _GenericQueueItem<TItem>;
    }

    queue.enqueue(value);
    if (first) {
      _queueSelectorQueue.addFirst(TItem);
    } else {
      _queueSelectorQueue.addLast(TItem);
    }
  }
}
