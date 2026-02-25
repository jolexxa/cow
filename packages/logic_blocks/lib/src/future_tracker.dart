part of 'logic_block.dart';

/// Tracks in-flight [Future]s and exposes a single [future] that completes
/// when all tracked futures have finished.
///
/// Use [trackFuture] to register a future. The aggregate [future] completes
/// once every tracked future has resolved (successfully or with an error).
/// After all tracked futures complete, the tracker resets automatically for
/// the next cycle.
class FutureTracker {
  int _pending = 0;
  Completer<void> _completer = Completer<void>()..complete();

  /// A [Future] that completes when all currently tracked futures have
  /// finished. Returns an already-completed future if nothing is tracked.
  Future<void> get future => _completer.future;

  /// Tracks [f] so that [future] will not complete until [f] has.
  void trackFuture(Future<void> f) {
    _pending++;

    if (_completer.isCompleted) {
      _completer = Completer<void>();
    }

    unawaited(
      f.then<void>((_) {}, onError: (_) {}).whenComplete(() {
        _pending--;
        if (_pending == 0) {
          _completer.complete();
        }
      }),
    );
  }

  /// Resets the tracker, completing any pending aggregate future immediately.
  void reset() {
    _pending = 0;
    if (!_completer.isCompleted) {
      _completer.complete();
    }
    _completer = Completer<void>()..complete();
  }
}
