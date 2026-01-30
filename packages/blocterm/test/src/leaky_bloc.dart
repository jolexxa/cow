import 'dart:async';

import 'package:bloc/bloc.dart';

class LeakyBloc implements BlocBase<int> {
  LeakyBloc([this._state = 0]);

  int _state;
  final _stream = _LeakyStream<int>();
  bool _isClosed = false;

  @override
  int get state => _state;

  @override
  Stream<int> get stream => _stream;

  @override
  bool get isClosed => _isClosed;

  @override
  Future<void> close() async {
    _isClosed = true;
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  void onChange(Change<int> change) {}

  @override
  void onError(Object error, StackTrace stackTrace) {}

  @override
  void emit(int value) {
    _state = value;
    _stream.add(value);
  }
}

class _LeakyStream<T> extends Stream<T> {
  final List<void Function(T)> _listeners = <void Function(T)>[];

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (onData != null) {
      _listeners.add(onData);
    }
    return _LeakySubscription<T>();
  }

  void add(T value) {
    for (final listener in List<void Function(T)>.from(_listeners)) {
      listener(value);
    }
  }
}

class _LeakySubscription<T> implements StreamSubscription<T> {
  bool _isPaused = false;

  @override
  Future<void> cancel() async {}

  @override
  void onData(void Function(T data)? handleData) {}

  @override
  void onError(Function? handleError) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void pause([Future<void>? resumeSignal]) {
    _isPaused = true;
    if (resumeSignal != null) {
      unawaited(resumeSignal.then((_) => resume()));
    }
  }

  @override
  void resume() {
    _isPaused = false;
  }

  @override
  bool get isPaused => _isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) {
    return Future<E>.value(futureValue as E);
  }
}
