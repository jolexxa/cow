// For clarity.
// ignore_for_file: cascade_invocations

import 'dart:async';

import 'package:logic_blocks/logic_blocks.dart';
import 'package:test/test.dart';

void main() {
  group('$FutureTracker', () {
    late FutureTracker tracker;

    setUp(() {
      tracker = FutureTracker();
    });

    test('future is completed when nothing is tracked', () {
      expect(tracker.future, completion(isNull));
    });

    test('future is pending while a tracked future is in-flight', () {
      final completer = Completer<void>();

      tracker.trackFuture(completer.future);

      // The aggregate future should not yet be complete.
      var done = false;
      unawaited(tracker.future.then((_) => done = true));

      expect(done, isFalse);

      // Clean up.
      completer.complete();
    });

    test('future completes when all tracked futures finish', () async {
      final c1 = Completer<void>();
      final c2 = Completer<void>();

      tracker.trackFuture(c1.future);
      tracker.trackFuture(c2.future);

      var done = false;
      unawaited(tracker.future.then((_) => done = true));

      c1.complete();
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);

      c2.complete();
      await tracker.future;
      expect(done, isTrue);
    });

    test('resets for next cycle after completion', () async {
      final c1 = Completer<void>();

      tracker.trackFuture(c1.future);
      c1.complete();
      await tracker.future;

      // New cycle — fresh completer.
      final c2 = Completer<void>();
      tracker.trackFuture(c2.future);

      var done = false;
      unawaited(tracker.future.then((_) => done = true));
      expect(done, isFalse);

      c2.complete();
      await tracker.future;
      expect(done, isTrue);
    });

    test('tracks futures that complete with errors', () async {
      final completer = Completer<void>();

      tracker.trackFuture(completer.future);

      completer.completeError(Exception('boom'));
      await tracker.future;

      // Aggregate future should complete even though the tracked
      // future errored.
    });

    test('reset completes pending aggregate future', () async {
      final completer = Completer<void>();

      tracker.trackFuture(completer.future);

      tracker.reset();

      await tracker.future;

      // Clean up the dangling completer so zone doesn't complain.
      completer.complete();
    });

    test('reset on idle tracker is a no-op', () {
      tracker.reset();
      expect(tracker.future, completion(isNull));
    });
  });
}
