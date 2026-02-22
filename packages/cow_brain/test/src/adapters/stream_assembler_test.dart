import 'package:cow_brain/src/adapters/stream_assembler.dart';
import 'package:cow_brain/src/adapters/stream_chunk.dart';
import 'package:test/test.dart';

void main() {
  group('StreamAssembler', () {
    test('addText with empty piece returns null before yield boundary', () {
      final assembler = StreamAssembler(stopSequences: const []);

      // 15 empty calls — below the 16-step boundary, should all return null.
      for (var i = 0; i < 15; i++) {
        expect(assembler.addText(''), isNull);
      }
    });

    test('addText with empty piece triggers heartbeat at boundary', () {
      final _ = StreamAssembler(stopSequences: const []);

      // First, accrue some token count delta via normal text so the
      // boundary chunk has something to emit.
      // We use a very long stop sequence so pending text is held in the guard.
      final guardAssembler = StreamAssembler(
        stopSequences: ['XXXXXXXXXXXXXXXXXXXXX'],
      );

      // Add 15 empty tokens — no yield yet.
      for (var i = 0; i < 15; i++) {
        guardAssembler.addText('a'); // produces a text piece
      }
      // Clear by flushing to reset step count, then do 16 empty calls.
      guardAssembler.flush();

      // Fresh assembler: feed 16 empty pieces — the 16th should trigger a
      // heartbeat chunk since tokenCountDelta has been accumulating.
      final emptyAssembler = StreamAssembler(
        stopSequences: const [],
      );
      StreamChunk? lastChunk;
      for (var i = 0; i < 16; i++) {
        lastChunk = emptyAssembler.addText('');
      }
      // At step 16 the boundary fires. tokenCountDelta == 16 > 0, so a chunk
      // is returned.
      expect(lastChunk, isNotNull);
      expect(lastChunk!.text, '');
      expect(lastChunk.tokenCountDelta, 16);
    });

    test('addText returns null on boundary when tokenCountDelta is zero', () {
      // This covers the path where _checkYieldBoundary fires but
      // tokenCountDelta == 0 (the delta was already flushed by a text chunk).
      // We do that by yielding a real chunk at step 1, resetting the counter,
      // then filling up 16 empty steps.
      final assembler = StreamAssembler(
        stopSequences: const [],
      );

      // Emit 'hello' — this yields a chunk and resets tokenCountDelta to 0.
      final chunk = assembler.addText('hello');
      expect(chunk, isNotNull);
      expect(chunk!.tokenCountDelta, 1);

      // Now call addText('') 16 more times. tokenCountDelta stays 0 because
      // no new text increments it between boundary checks...
      // Actually each addText('') increments tokenCountDelta by 1 (line 39),
      // then calls _checkYieldBoundary. At step 16 it fires and emits the
      // accumulated delta.
      StreamChunk? result;
      for (var i = 0; i < 16; i++) {
        result = assembler.addText('');
      }
      expect(result, isNotNull);
      expect(result!.tokenCountDelta, 16);
    });

    test('flush emits remaining pending text and leftover token count', () {
      // Use a stop sequence of length 4 => guardLength = 3.
      // 'hi' is only 2 chars, so flushLength = 2 - 3 = -1 (no flush).
      // The whole 'hi' stays in the guard buffer and is emitted by flush().
      final assembler = StreamAssembler(
        stopSequences: ['STOP'],
      );

      // addText returns null because all 2 chars stay in the guard.
      final chunk = assembler.addText('hi');
      expect(chunk, isNull);

      final chunks = assembler.flush();

      expect(chunks, isNotEmpty);
      expect(chunks.first.text, 'hi');
    });

    test('stopped is set when stop sequence is detected', () {
      final assembler = StreamAssembler(stopSequences: const ['END'])
        ..addText('some text')
        ..addText('END');
      expect(assembler.stopped, isTrue);
    });

    test('addText does not split supplementary-plane emoji', () {
      // Guard length of 3 (stop sequence length 4 - 1).
      // Feed 'ab\u{1F52E}' (4 code units: a, b, high surrogate, low surrogate).
      // flushLength = 4 - 3 = 1 without the fix, which would be safe.
      // But with 'a\u{1F52E}' (3 code units), flushLength = 3 - 3 = 0 (no flush).
      // The tricky case: guard=1 (stop='XX', guardLength=1), text='a\u{1F52E}'.
      // pending.length = 3, flushLength = 3 - 1 = 2.
      // Code unit at index 1 is the HIGH surrogate (0xD83D).
      // Without fix: substring(0,2) splits the pair!
      final assembler = StreamAssembler(
        stopSequences: ['XX'],
      );

      final chunk = assembler.addText('a\u{1F52E}');
      expect(chunk, isNotNull);

      // The visible text must contain the full emoji, not a lone surrogate.
      final text = chunk!.text;
      // Verify no lone surrogates: encoding to UTF-8 and back should roundtrip.
      final encoded = text.runes.toList();
      for (final rune in encoded) {
        expect(
          rune,
          isNot(equals(0xFFFD)),
          reason: 'Output contains U+FFFD replacement character',
        );
        expect(
          rune < 0xD800 || rune > 0xDFFF,
          isTrue,
          reason: 'Output contains lone surrogate',
        );
      }
      expect(text, contains('\u{1F52E}'));
    });
  });
}
