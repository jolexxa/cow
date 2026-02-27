import 'package:cow_brain/src/adapters/token_decoder.dart';
import 'package:test/test.dart';

void main() {
  group('TokenDecoder', () {
    test('feedBytes returns empty-token for incomplete multi-byte UTF-8', () {
      final decoder = TokenDecoder(stopSequences: const []);

      // 0xC2 starts a 2-byte UTF-8 sequence. The chunked decoder produces
      // an empty string (no complete character yet), so feedBytes returns
      // via the piece.isEmpty → addEmptyToken() path.
      final chunk = decoder.feedBytes([0xC2]);
      expect(chunk, isNull);

      // Complete the sequence → produces ©.
      final completed = decoder.feedBytes([0xA9]);
      expect(completed, isNotNull);
      expect(completed!.text, '©');

      decoder.finish();
    });
  });
}
